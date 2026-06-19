#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

I3_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/i3"
I3_CONFIG="${I3_DIR}/config"
I3_SCRIPTS_DIR="${I3_DIR}/scripts"
I3_AUTOSTART="${I3_SCRIPTS_DIR}/i3_autostart"
SCREENLAYOUT_DIR="$HOME/.screenlayout"
SCREENLAYOUT_FILE="${SCREENLAYOUT_DIR}/pantallas.sh"
POLYBAR_SHAPES_MODULES_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/polybar/shapes/modules.ini"
POLYBAR_SHAPES_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/polybar/shapes/config.ini"
WAL_TEMPLATES_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/wal/templates"
WAL_ALACRITTY_TEMPLATE="${WAL_TEMPLATES_DIR}/colors-alacritty.toml"
ALACRITTY_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/alacritty/alacritty.toml"
I3_GAP_SIZE="${I3_GAP_SIZE:-12}"
BACKUP_ROOT="${I3_DIR}/.cachyos-i3-backups"
LATEST_MANIFEST_LINK="${BACKUP_ROOT}/latest.manifest"

MANAGED_BEGIN="# >>> cachyos-i3 managed block >>>"
MANAGED_END="# <<< cachyos-i3 managed block <<<"

SKIP_INSTALL=0
NON_INTERACTIVE=0
REVERT=0
DRY_RUN=0
COMMAND="setup"
SUBCOMMAND_ARGS=()

usage() {
  cat <<'EOF'
Uso:
  ./scripts/i3_config.sh [subcomando] [opciones-globales] [argumentos]

Subcomandos:
  setup             Ejecuta la configuracion completa (por defecto).
  deps-check        Muestra dependencias opcionales faltantes.
  deps-install      Instala dependencias faltantes o las indicadas en argumentos.
  wal [DIR]         Regenera cache de pywal usando DIR (o wallpapers detectados).
  alacritty         Aplica solo plantilla/import de pywal en Alacritty.
  colorscheme       Ejecuta flujo de wallpapers + pywal + Alacritty.
  helpers-install   Instala/actualiza scripts helper y autostart.
  screenlayout      Genera layout multimonitor cuando aplique.
  picom-config      Aplica solo ajustes de picom.
  polybar-update    Aplica solo ajustes de polybar shapes.
  i3-patch          Aplica solo binds + bloque gestionado en i3 config.
  backup-list       Lista backups disponibles.
  backup-restore    Restaura backup por timestamp, manifiesto o latest.
  revert            Revierte cambios usando el ultimo backup.

Opciones:
  --skip-install   No intentar instalar dependencias faltantes.
  --yes            Ejecutar sin preguntas interactivas (continua sin instalar faltantes).
  --revert         Revierte los cambios usando el ultimo backup.
  --dry-run        Simula cambios sin modificar archivos ni instalar paquetes.
  -h, --help       Muestra esta ayuda.
EOF
}

if (($# > 0)) && [[ "$1" != -* ]]; then
  COMMAND="$1"
  shift
fi

while (($# > 0)); do
  case "$1" in
    --skip-install)
      SKIP_INSTALL=1
      shift
      ;;
    --yes)
      NON_INTERACTIVE=1
      shift
      ;;
    --revert)
      REVERT=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      SUBCOMMAND_ARGS+=("$1")
      shift
      ;;
  esac
done

log() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
err() { echo "[ERROR] $*" >&2; }
dry() { echo "[DRY-RUN] $*" >&2; }

mkdir -p "$BACKUP_ROOT"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${BACKUP_ROOT}/${TIMESTAMP}"
MANIFEST="${BACKUP_DIR}/manifest.txt"

backup_started=0

ensure_backup_session() {
  if [[ $DRY_RUN -eq 1 ]]; then
    return 0
  fi

  if [[ $backup_started -eq 0 ]]; then
    mkdir -p "$BACKUP_DIR"
    : > "$MANIFEST"
    backup_started=1
  fi
}

record_new_file() {
  if [[ $DRY_RUN -eq 1 ]]; then
    dry "Se crearia archivo: $1"
    return 0
  fi

  ensure_backup_session
  local target="$1"
  if ! grep -Fq "NEW|${target}" "$MANIFEST" 2>/dev/null; then
    printf 'NEW|%s\n' "$target" >> "$MANIFEST"
  fi
}

backup_file_once() {
  local target="$1"
  if [[ ! -e "$target" ]]; then
    return 0
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "Se respaldaria archivo: $target"
    return 0
  fi

  ensure_backup_session

  if grep -Fq "FILE|${target}|" "$MANIFEST" 2>/dev/null; then
    return 0
  fi

  local safe_name
  safe_name="$(echo "$target" | sed 's#^/#root/#; s#/#__#g')"
  local backup_path="${BACKUP_DIR}/${safe_name}"

  cp -a "$target" "$backup_path"
  printf 'FILE|%s|%s\n' "$target" "$backup_path" >> "$MANIFEST"
}

finalize_backup_manifest() {
  if [[ $DRY_RUN -eq 1 ]]; then
    dry "Se finalizaria manifiesto de backup"
    return 0
  fi

  if [[ $backup_started -eq 1 ]]; then
    ln -sfn "$MANIFEST" "$LATEST_MANIFEST_LINK"
    log "Backup creado en: $BACKUP_DIR"
  fi
}

restore_latest_backup() {
  if [[ ! -L "$LATEST_MANIFEST_LINK" && ! -f "$LATEST_MANIFEST_LINK" ]]; then
    err "No existe backup previo para revertir."
    exit 1
  fi

  local manifest_path
  manifest_path="$(readlink -f "$LATEST_MANIFEST_LINK")"

  if [[ ! -f "$manifest_path" ]]; then
    err "El manifiesto de backup no es valido: $manifest_path"
    exit 1
  fi

  log "Revirtiendo cambios desde: $manifest_path"

  restore_from_manifest "$manifest_path"
}

restore_from_manifest() {
  local manifest_path="$1"

  if [[ ! -f "$manifest_path" ]]; then
    err "El manifiesto de backup no es valido: $manifest_path"
    return 1
  fi

  while IFS='|' read -r kind p1 p2; do
    case "$kind" in
      FILE)
        if [[ -f "$p2" || -d "$p2" ]]; then
          if [[ $DRY_RUN -eq 1 ]]; then
            dry "Se restauraria: $p1"
          else
            mkdir -p "$(dirname "$p1")"
            rm -rf "$p1"
            cp -a "$p2" "$p1"
            log "Restaurado: $p1"
          fi
        else
          warn "Backup no encontrado para: $p1"
        fi
        ;;
      NEW)
        if [[ -e "$p1" ]]; then
          if [[ $DRY_RUN -eq 1 ]]; then
            dry "Se eliminaria (creado por script): $p1"
          else
            rm -rf "$p1"
            log "Eliminado (creado por script): $p1"
          fi
        fi
        ;;
      "")
        ;;
      *)
        warn "Entrada desconocida en manifiesto: $kind"
        ;;
    esac
  done < "$manifest_path"

  log "Reversion completada."
}

list_backups() {
  local manifests=()
  local latest_manifest=""

  if [[ -L "$LATEST_MANIFEST_LINK" || -f "$LATEST_MANIFEST_LINK" ]]; then
    latest_manifest="$(readlink -f "$LATEST_MANIFEST_LINK" 2>/dev/null || true)"
  fi

  shopt -s nullglob
  manifests=("$BACKUP_ROOT"/*/manifest.txt)
  shopt -u nullglob

  if ((${#manifests[@]} == 0)); then
    warn "No hay backups registrados en: $BACKUP_ROOT"
    return 1
  fi

  log "Backups disponibles en: $BACKUP_ROOT"

  local manifest
  local ts
  local marker
  for manifest in "${manifests[@]}"; do
    ts="$(basename "$(dirname "$manifest")")"
    marker=""
    if [[ -n "$latest_manifest" && "$(readlink -f "$manifest")" == "$latest_manifest" ]]; then
      marker=" [latest]"
    fi
    printf '  - %s%s\n' "$ts" "$marker"
  done
}

command_backup_list() {
  list_backups
}

command_backup_restore() {
  local backup_id="${SUBCOMMAND_ARGS[0]:-latest}"
  local manifest_path=""

  case "$backup_id" in
    latest)
      restore_latest_backup
      return 0
      ;;
    *)
      if [[ -f "$backup_id" ]]; then
        manifest_path="$backup_id"
      elif [[ -f "$BACKUP_ROOT/$backup_id/manifest.txt" ]]; then
        manifest_path="$BACKUP_ROOT/$backup_id/manifest.txt"
      else
        err "No se encontro backup: $backup_id"
        warn "Usa backup-list para ver timestamps disponibles."
        return 1
      fi
      ;;
  esac

  log "Revirtiendo cambios desde: $manifest_path"
  restore_from_manifest "$manifest_path"
}

if [[ $REVERT -eq 1 || "$COMMAND" == "revert" ]]; then
  restore_latest_backup
  exit 0
fi

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Modulos extraidos por dominio.
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/modules/dependencies.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/modules/colorscheme.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/modules/screenlayout.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/modules/picom.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/modules/helpers.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/modules/polybar.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/modules/i3_patch.sh"

safe_write_file() {
  local target="$1"
  local content="$2"

  if [[ -e "$target" ]]; then
    backup_file_once "$target"
  else
    record_new_file "$target"
    if [[ $DRY_RUN -ne 1 ]]; then
      mkdir -p "$(dirname "$target")"
    fi
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "Se escribiria archivo: $target"
    return 0
  fi

  printf '%s' "$content" > "$target"
}

replace_or_append_line() {
  local file="$1"
  local match_regex="$2"
  local replacement="$3"

  local tmp
  tmp="$(mktemp)"
  if [[ -f "$file" ]] && grep -Eq "$match_regex" "$file"; then
    sed -E "s|$match_regex|$replacement|" "$file" > "$tmp"
  else
    cat "$file" > "$tmp"
    printf '\n%s\n' "$replacement" >> "$tmp"
  fi

  backup_file_once "$file"
  cat "$tmp" > "$file"
  rm -f "$tmp"
}

remove_managed_block() {
  local file="$1"
  if [[ $DRY_RUN -eq 1 ]]; then
    dry "Se limpiaria bloque gestionado en: $file"
    return 0
  fi

  local tmp
  tmp="$(mktemp)"

  awk -v begin="$MANAGED_BEGIN" -v end="$MANAGED_END" '
    $0 == begin {inblock=1; next}
    $0 == end {inblock=0; next}
    !inblock {print}
  ' "$file" > "$tmp"

  backup_file_once "$file"
  cat "$tmp" > "$file"
  rm -f "$tmp"
}

append_managed_block() {
  local file="$1"
  local block="$2"

  remove_managed_block "$file"

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "Se agregaria bloque gestionado en: $file"
    return 0
  fi

  {
    echo
    echo "$MANAGED_BEGIN"
    echo "$block"
    echo "$MANAGED_END"
    echo
  } >> "$file"
}

ensure_i3_config_exists() {
  if [[ -f "$I3_CONFIG" ]]; then
    return 0
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "Se crearia config base de i3: $I3_CONFIG"
    return 0
  fi

  mkdir -p "$I3_DIR"
  record_new_file "$I3_CONFIG"

  cat > "$I3_CONFIG" <<'EOF'
set $mod Mod4
font pango:Hack 9
floating_modifier $mod

set $term alacritty
bindsym $mod+Return exec $term
EOF

  log "Creado config base de i3: $I3_CONFIG"
}

command_setup() {
  if [[ $DRY_RUN -eq 1 ]]; then
    log "Modo dry-run activo: no se realizaran cambios reales."
  fi

  ensure_i3_config_exists

  if [[ ! -f "$I3_CONFIG" ]]; then
    err "No existe i3 config en: $I3_CONFIG"
    err "Sin archivo real no se puede simular cambios de contenido."
    exit 1
  fi

  local required_cmds=(sed awk grep cp chmod mkdir)
  local optional_cmds=(rofi picom xrandr xborder-git i3-layouts wallutils python nextcloud kwallet-pam polybar-themes-git mpd wal)
  local missing=()
  local c

  for c in "${required_cmds[@]}"; do
    if ! command_exists "$c"; then
      err "Falta dependencia critica: $c"
      exit 1
    fi
  done

  mapfile -t missing < <(collect_missing_dependencies "${optional_cmds[@]}")

  if ((${#missing[@]} > 0)); then
    if [[ $SKIP_INSTALL -eq 1 ]]; then
      print_missing_dependencies "${missing[@]}"
      warn "Se omite instalacion de dependencias por --skip-install"
    else
      local action
      action="$(ask_missing_dependency_action "${missing[@]}")"
      case "$action" in
        1)
          if ! install_missing_dependencies "${missing[@]}"; then
            warn "No se pudieron instalar todas las dependencias."
            if [[ $NON_INTERACTIVE -eq 1 ]]; then
              warn "Modo --yes: continuando sin instalar."
            else
              read -r -p "Quieres continuar igualmente? [s/N]: " cont
              if [[ "${cont,,}" != "s" ]]; then
                err "Abortado por el usuario."
                exit 1
              fi
            fi
          fi
          ;;
        2)
          warn "Continuando sin instalar dependencias faltantes."
          ;;
        3)
          err "Abortado por el usuario."
          exit 1
          ;;
      esac
    fi
  fi

  command_helpers_install
  command_colorscheme
  command_screenlayout
  command_i3_patch
  command_picom_config
  command_polybar_update

  if [[ $DRY_RUN -eq 0 ]]; then
    log "Configuracion aplicada correctamente."
  fi
}

command_deps_check() {
  local optional_cmds=(rofi picom xrandr xborder-git i3-layouts wallutils python nextcloud kwallet-pam polybar-themes-git mpd wal)
  local missing=()

  mapfile -t missing < <(collect_missing_dependencies "${optional_cmds[@]}")

  if ((${#missing[@]} == 0)); then
    log "No faltan dependencias opcionales."
    return 0
  fi

  print_missing_dependencies "${missing[@]}"
  return 1
}

command_deps_install() {
  local targets=()

  if [[ $SKIP_INSTALL -eq 1 ]]; then
    warn "Se omite instalacion por --skip-install"
    return 0
  fi

  if ((${#SUBCOMMAND_ARGS[@]} > 0)); then
    targets=("${SUBCOMMAND_ARGS[@]}")
  else
    local optional_cmds=(rofi picom xrandr xborder-git i3-layouts wallutils python nextcloud kwallet-pam polybar-themes-git mpd wal)
    mapfile -t targets < <(collect_missing_dependencies "${optional_cmds[@]}")
  fi

  if ((${#targets[@]} == 0)); then
    log "No hay dependencias para instalar."
    return 0
  fi

  install_missing_dependencies "${targets[@]}"
}

command_wal() {
  local wallpaper_dir=""
  if ((${#SUBCOMMAND_ARGS[@]} > 0)); then
    wallpaper_dir="${SUBCOMMAND_ARGS[0]}"
  else
    wallpaper_dir="$(copy_wallpapers)"
  fi

  ensure_wal_alacritty_template
  regenerate_wal_cache "$wallpaper_dir"
}

command_alacritty() {
  ensure_wal_alacritty_template
  ensure_alacritty_wal_import
}

command_colorscheme() {
  local wallpaper_dir
  wallpaper_dir="$(copy_wallpapers)"

  ensure_wal_alacritty_template
  regenerate_wal_cache "$wallpaper_dir"
  ensure_alacritty_wal_import
}

command_helpers_install() {
  ensure_helper_scripts
  update_i3_autostart_if_exists
}

command_screenlayout() {
  ensure_i3_config_exists
  create_multimonitor_layout_if_needed >/dev/null
}

command_picom_config() {
  update_picom_corner_radius
  update_picom_blur_exclude
}

command_polybar_update() {
  ensure_polybar_shapes_tray_module
  ensure_polybar_shapes_modules_right_tray
}

dispatch_command() {
  case "$COMMAND" in
    setup)
      command_setup
      ;;
    deps-check)
      command_deps_check
      ;;
    deps-install)
      command_deps_install
      ;;
    wal)
      command_wal
      ;;
    alacritty)
      command_alacritty
      ;;
    colorscheme)
      command_colorscheme
      ;;
    helpers-install)
      command_helpers_install
      ;;
    screenlayout)
      command_screenlayout
      ;;
    picom-config)
      command_picom_config
      ;;
    polybar-update)
      command_polybar_update
      ;;
    i3-patch)
      command_i3_patch
      ;;
    backup-list)
      command_backup_list
      ;;
    backup-restore)
      command_backup_restore
      ;;
    *)
      err "Subcomando no reconocido: $COMMAND"
      usage
      return 1
      ;;
  esac
}

dispatch_command

if [[ $DRY_RUN -eq 1 ]]; then
  log "Dry-run completado."
fi

finalize_backup_manifest
