#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

I3_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/i3"
I3_CONFIG="${I3_DIR}/config"
I3_SCRIPTS_DIR="${I3_DIR}/scripts"
I3_AUTOSTART="${I3_SCRIPTS_DIR}/i3_autostart"
SCREENLAYOUT_DIR="$HOME/.screenlayout"
SCREENLAYOUT_FILE="${SCREENLAYOUT_DIR}/my-layout.sh"
I3_GAP_SIZE="${I3_GAP_SIZE:-12}"
BACKUP_ROOT="${I3_DIR}/.cachyos-i3-backups"
LATEST_MANIFEST_LINK="${BACKUP_ROOT}/latest.manifest"

MANAGED_BEGIN="# >>> cachyos-i3 managed block >>>"
MANAGED_END="# <<< cachyos-i3 managed block <<<"

SKIP_INSTALL=0
NON_INTERACTIVE=0
REVERT=0
DRY_RUN=0

usage() {
  cat <<'EOF'
Uso:
  ./scripts/i3_config.sh [opciones]

Opciones:
  --skip-install   No intentar instalar dependencias faltantes.
  --yes            Ejecutar sin preguntas interactivas (continua sin instalar faltantes).
  --revert         Revierte los cambios usando el ultimo backup.
  --dry-run        Simula cambios sin modificar archivos ni instalar paquetes.
  -h, --help       Muestra esta ayuda.
EOF
}

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
      echo "[ERROR] Opcion no reconocida: $1" >&2
      usage
      exit 1
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

if [[ $REVERT -eq 1 ]]; then
  restore_latest_backup
  exit 0
fi

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

ask_missing_dependency_action() {
  local missing=($@)
  echo
  warn "Faltan dependencias: ${missing[*]}"
  echo "Elige una opcion:"
  echo "  1) Intentar instalar faltantes"
  echo "  2) Continuar sin instalar"
  echo "  3) Detener script"

  if [[ $NON_INTERACTIVE -eq 1 ]]; then
    echo "2"
    return 0
  fi

  while true; do
    read -r -p "Seleccion [1-3]: " choice
    case "$choice" in
      1|2|3)
        echo "$choice"
        return 0
        ;;
      *)
        warn "Seleccion no valida."
        ;;
    esac
  done
}

install_missing_dependencies() {
  local missing=($@)

  if ((${#missing[@]} == 0)); then
    return 0
  fi

  local pkg_manager=""
  if command_exists paru; then
    pkg_manager="paru"
  elif command_exists yay; then
    pkg_manager="yay"
  elif command_exists pacman; then
    pkg_manager="pacman"
  fi

  if [[ -z "$pkg_manager" ]]; then
    warn "No se encontro gestor de paquetes compatible (paru/yay/pacman)."
    return 1
  fi

  local packages=()
  local cmd
  for cmd in "${missing[@]}"; do
    case "$cmd" in
      rofi) packages+=(rofi) ;;
      picom) packages+=(picom) ;;
      xrandr) packages+=(xorg-xrandr) ;;
      xborders) packages+=(xborders) ;;
      i3-layouts) packages+=(i3-layouts) ;;
      setwallpaper) packages+=(setwallpaper) ;;
      nextcloud) packages+=(nextcloud-client) ;;
      kwallet-pam) packages+=(kwallet-pam) ;;
      python) packages+=(python) ;;
      *) packages+=("$cmd") ;;
    esac
  done

  local unique_packages=()
  local seen=""
  local pkg
  for pkg in "${packages[@]}"; do
    if [[ " $seen " != *" $pkg "* ]]; then
      unique_packages+=("$pkg")
      seen+=" $pkg"
    fi
  done

  log "Intentando instalar: ${unique_packages[*]}"

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "Se instalarian paquetes: ${unique_packages[*]}"
    return 0
  fi

  case "$pkg_manager" in
    paru|yay)
      "$pkg_manager" -S --needed --noconfirm "${unique_packages[@]}"
      ;;
    pacman)
      sudo pacman -S --needed --noconfirm "${unique_packages[@]}"
      ;;
  esac
}

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

verify_screenlayout_config_applied() {
  local has_multi="$1"

  if [[ "$has_multi" != "1" ]]; then
    return 0
  fi

  local expected_line="exec --no-startup-id ${SCREENLAYOUT_FILE}"

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "Se verificaria configuracion de screenlayout en: $I3_CONFIG"
    return 0
  fi

  if grep -Fq "$expected_line" "$I3_CONFIG"; then
    log "Screenlayout configurado en i3 config: $SCREENLAYOUT_FILE"
  else
    err "No se aplico la configuracion de screenlayout en: $I3_CONFIG"
    warn "Verifica permisos o contenido del bloque gestionado e intenta nuevamente."
  fi
}

update_picom_corner_radius() {
  local candidate=""
  local path
  for path in "$I3_DIR/picom.conf" "$HOME/.config/picom/picom.conf"; do
    if [[ -f "$path" ]]; then
      candidate="$path"
      break
    fi
  done

  if [[ -z "$candidate" ]]; then
    warn "No se encontro picom.conf. Se omite corner-radius."
    return 0
  fi

  local tmp
  tmp="$(mktemp)"

  awk '
    BEGIN { inblock=0 }
    {
      if ($0 ~ /#-cr-start/) inblock=1
      if (inblock && $0 ~ /^[[:space:]]*corner-radius[[:space:]]*=/) {
        sub(/=.*/, "= 12;")
      }
      print
      if ($0 ~ /#-cr-end/) inblock=0
    }
  ' "$candidate" > "$tmp"

  if ! cmp -s "$candidate" "$tmp"; then
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "Se actualizaria corner-radius a 12 en: $candidate"
    else
      backup_file_once "$candidate"
      cat "$tmp" > "$candidate"
      log "Actualizado corner-radius en: $candidate"
    fi
  else
    log "corner-radius ya estaba configurado en: $candidate"
  fi

  rm -f "$tmp"
}

update_picom_blur_exclude() {
  local candidate=""
  local path
  for path in "$I3_DIR/picom.conf" "$HOME/.config/picom/picom.conf"; do
    if [[ -f "$path" ]]; then
      candidate="$path"
      break
    fi
  done

  if [[ -z "$candidate" ]]; then
    warn "No se encontro picom.conf. Se omite blur-background-exclude."
    return 0
  fi

  local entries=(
    "role = 'xborder'"
    "class_g = 'xborder'"
    "name = 'xborder'"
  )

  # Verificar si ya existen todas las entradas
  local all_present=1
  local entry
  for entry in "${entries[@]}"; do
    if ! grep -Fq "$entry" "$candidate"; then
      all_present=0
      break
    fi
  done

  if [[ $all_present -eq 1 ]]; then
    log "blur-background-exclude xborder ya configurado en: $candidate"
    return 0
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "Se agregarian entradas xborder a blur-background-exclude en: $candidate"
    return 0
  fi

  local tmp
  tmp="$(mktemp)"

  # Inserta las entradas faltantes dentro del bloque blur-background-exclude = [...]
  awk -v entries="role = 'xborder'|class_g = 'xborder'|name = 'xborder'" '
    BEGIN {
      inblock = 0
      done = 0
      n = split(entries, arr, "|")
    }
    !done && /blur-background-exclude[[:space:]]*=/ { inblock = 1 }
    inblock && /\]/ && !done {
      for (i = 1; i <= n; i++) {
        found = 0
        while ((getline line < FILENAME) > 0) { close(FILENAME); break }
        found = 0
      }
      # Agregar entradas que no esten presentes antes del cierre
      for (i = 1; i <= n; i++) {
        if (!seen[arr[i]]) {
          print "  " arr[i] ","
        }
      }
      done = 1
    }
    { seen[$0] = 1; print }
  ' "$candidate" > /dev/null

  # Usar python3 para la manipulacion segura del bloque
  python3 - "$candidate" "$tmp" <<'PYEOF'
import sys, re

src = sys.argv[1]
dst = sys.argv[2]

new_entries = [
    "  role = 'xborder'",
    "  class_g = 'xborder'",
    "  name = 'xborder'",
]

with open(src, 'r') as f:
    content = f.read()

# Localizar el bloque blur-background-exclude = [ ... ]
pattern = re.compile(
    r'(blur-background-exclude\s*=\s*\[)(.*?)(\])',
    re.DOTALL
)

def insert_missing(m):
    header = m.group(1)
    body   = m.group(2)
    footer = m.group(3)
    for ne in new_entries:
        key = ne.strip().rstrip(',')
        if key not in body:
            # Agregar antes del cierre, con coma si el body ya tiene contenido
            body = body.rstrip()
            if body and not body.endswith(','):
                body += ','
            body += '\n' + ne + ',\n'
    return header + body + footer

new_content = pattern.sub(insert_missing, content, count=1)

with open(dst, 'w') as f:
    f.write(new_content)
PYEOF

  if ! cmp -s "$candidate" "$tmp"; then
    backup_file_once "$candidate"
    cat "$tmp" > "$candidate"
    log "Agregadas entradas xborder a blur-background-exclude en: $candidate"
  else
    log "blur-background-exclude xborder ya estaba presente en: $candidate"
  fi

  rm -f "$tmp"
}

detect_wallpaper_dir() {
  local d1="$HOME/Images/wallpapers"
  local d2="$HOME/Imágenes/wallpapers"

  if [[ -d "$d1" ]]; then
    echo "$d1"
    return 0
  fi
  if [[ -d "$d2" ]]; then
    echo "$d2"
    return 0
  fi

  echo "$d1"
}

copy_wallpapers() {
  local src_dir="${REPO_ROOT}/wallpapers"
  local dst_dir
  dst_dir="$(detect_wallpaper_dir)"

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "Se aseguraria directorio de wallpapers: $dst_dir"
  else
    mkdir -p "$dst_dir"
  fi
  if [[ ! -d "$src_dir" ]]; then
    warn "No existe el directorio de wallpapers en el repo: $src_dir"
    echo ""
    return 0
  fi

  shopt -s nullglob
  local files=("$src_dir"/*)
  shopt -u nullglob

  if ((${#files[@]} == 0)); then
    warn "No hay wallpapers para copiar en: $src_dir"
    echo ""
    return 0
  fi

  local f
  for f in "${files[@]}"; do
    if [[ -f "$f" ]]; then
      local target_file="${dst_dir}/$(basename "$f")"
      if [[ ! -e "$target_file" ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
          dry "Se copiaria wallpaper: $target_file"
        else
          cp -a "$f" "$target_file"
          log "Wallpaper copiado: $target_file"
        fi
      fi
    fi
  done

  echo "$dst_dir"
}

create_multimonitor_layout_if_needed() {
  if ! command_exists xrandr; then
    warn "xrandr no esta disponible. Se omite auto layout multimonitor."
    echo "0"
    return 0
  fi

  mapfile -t connected < <(xrandr --query | awk '/ connected/{print $1}')

  if ((${#connected[@]} < 2)); then
    log "Se detecto un solo monitor."
    echo "0"
    return 0
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "Se aseguraria directorio: $SCREENLAYOUT_DIR"
  else
    mkdir -p "$SCREENLAYOUT_DIR"
  fi
  if [[ -f "$SCREENLAYOUT_FILE" ]]; then
    backup_file_once "$SCREENLAYOUT_FILE"
  else
    record_new_file "$SCREENLAYOUT_FILE"
  fi

  local monitor_specs=()
  local primary_mon=""
  local primary_mode=""
  local primary_width=0
  local primary_area=0
  local mon

  for mon in "${connected[@]}"; do
    local mode
    mode="$(xrandr --query | awk -v m="$mon" '
      $1 == m && $2 == "connected" {inside=1; next}
      inside && $1 ~ /^[0-9]+x[0-9]+$/ {print $1; exit}
      inside && $1 !~ /^[0-9]+x[0-9]+$/ && NF == 0 {inside=0}
    ')"

    if [[ -z "$mode" ]]; then
      mode="1920x1080"
    fi

    local width
    local height
    local area

    width="${mode%x*}"
    height="${mode#*x}"

    if [[ "$width" =~ ^[0-9]+$ && "$height" =~ ^[0-9]+$ ]]; then
      area=$((width * height))
    else
      width=1920
      height=1080
      area=$((width * height))
    fi

    monitor_specs+=("${width}|${mon}|${mode}")

    if (( area > primary_area )); then
      primary_area=$area
      primary_mon="$mon"
      primary_mode="$mode"
      primary_width=$width
    fi
  done

  local cmd_lines=()
  local x_pos=0
  local ordered_specs=()

  # Ordena de izquierda a derecha por ancho, dejando la pantalla principal
  # (mayor resolucion) al final para que quede a la derecha.
  while IFS='|' read -r width mon mode; do
    if [[ "$mon" != "$primary_mon" ]]; then
      ordered_specs+=("${width}|${mon}|${mode}")
    fi
  done < <(printf '%s\n' "${monitor_specs[@]}" | sort -s -n -t '|' -k1,1)

  ordered_specs+=("${primary_width}|${primary_mon}|${primary_mode}")

  while IFS='|' read -r width mon mode; do
    if [[ "$mon" == "$primary_mon" ]]; then
      cmd_lines+=("       --output ${mon} --primary --mode ${mode} --pos ${x_pos}x0 --rotate normal \\")
    else
      cmd_lines+=("       --output ${mon} --mode ${mode} --pos ${x_pos}x0 --rotate normal \\")
    fi

    x_pos=$((x_pos + width))
  done < <(printf '%s\n' "${ordered_specs[@]}")

  if ((${#cmd_lines[@]} > 0)); then
    local last_index
    last_index=$((${#cmd_lines[@]} - 1))
    cmd_lines[$last_index]="${cmd_lines[$last_index]% \\}"
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "Se generaria layout multimonitor en: $SCREENLAYOUT_FILE"
  else
    {
      echo '#!/usr/bin/env bash'
      echo 'set -euo pipefail'
      echo
      echo 'xrandr \\'
      printf '%s\n' "${cmd_lines[@]}"
      echo
      echo 'echo "Configuracion multimonitor aplicada automaticamente"'
    } > "$SCREENLAYOUT_FILE"

    chmod +x "$SCREENLAYOUT_FILE"
    log "Generado layout multimonitor: $SCREENLAYOUT_FILE"
  fi
  echo "1"
}

ensure_helper_scripts() {
  if [[ $DRY_RUN -eq 1 ]]; then
    dry "Se aseguraria directorio de scripts i3: $I3_SCRIPTS_DIR"
  else
    mkdir -p "$I3_SCRIPTS_DIR"
  fi

  local helper
  for helper in i3_nzxt i3_cloud_storage i3_rofi_apps i3_polybar_set_theme i3_rofi_powermenu i3_rofi_polybar_theme; do
    local src="${SCRIPT_DIR}/apps/${helper}"
    local dst="${I3_SCRIPTS_DIR}/${helper}"

    if [[ ! -f "$src" ]]; then
      warn "No existe helper en repo: $src"
      continue
    fi

    if [[ -f "$dst" ]]; then
      if ! cmp -s "$src" "$dst"; then
        if [[ $DRY_RUN -eq 1 ]]; then
          dry "Se actualizaria helper: $dst"
        else
          backup_file_once "$dst"
          cp -a "$src" "$dst"
          log "Helper actualizado: $dst"
        fi
      fi
    else
      if [[ $DRY_RUN -eq 1 ]]; then
        dry "Se instalaria helper: $dst"
      else
        record_new_file "$dst"
        cp -a "$src" "$dst"
        log "Helper instalado: $dst"
      fi
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
      dry "Se aplicaria chmod +x a: $dst"
    else
      chmod +x "$dst"
    fi
  done
}

update_i3_autostart_if_exists() {
  if [[ ! -f "$I3_AUTOSTART" ]]; then
    return 0
  fi

  local block='\
# Launch NZXT
"$idir"/scripts/i3_nzxt

# Launch Cloud Storage
"$idir"/scripts/i3_cloud_storage\
'

  if grep -Fq '"$idir"/scripts/i3_nzxt' "$I3_AUTOSTART" && grep -Fq '"$idir"/scripts/i3_cloud_storage' "$I3_AUTOSTART"; then
    return 0
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "Se insertarian helpers en i3_autostart: $I3_AUTOSTART"
    return 0
  fi

  backup_file_once "$I3_AUTOSTART"

  # Limpia entradas viejas para evitar duplicados (Overgrive) y bloque previo.
  sed -i '/^# Launch NZXT$/d' "$I3_AUTOSTART"
  sed -i '/^# Launch Overgrive$/d' "$I3_AUTOSTART"
  sed -i '/^# Launch Cloud Storage$/d' "$I3_AUTOSTART"
  sed -i '/"\$idir"\/scripts\/i3_nzxt/d' "$I3_AUTOSTART"
  sed -i '/"\$idir"\/scripts\/i3_overgrive/d' "$I3_AUTOSTART"
  sed -i '/"\$idir"\/scripts\/i3_cloud_storage/d' "$I3_AUTOSTART"

  local tmp
  tmp="$(mktemp)"

  if grep -Fq '# Start mpd' "$I3_AUTOSTART"; then
    awk -v insert="$block" '
      $0 ~ /# Start mpd/ && !done { printf "%s\n", insert; done=1 }
      { print }
    ' "$I3_AUTOSTART" > "$tmp"
  else
    cat "$I3_AUTOSTART" > "$tmp"
    printf '\n%s\n' "$block" >> "$tmp"
  fi

  cat "$tmp" > "$I3_AUTOSTART"
  rm -f "$tmp"
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

main() {
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
  local optional_cmds=(rofi picom xrandr xborders i3-layouts setwallpaper python nextcloud kwallet-pam polybar-themes-git mpd)
  local missing=()

  local c
  for c in "${required_cmds[@]}"; do
    if ! command_exists "$c"; then
      err "Falta dependencia critica: $c"
      exit 1
    fi
  done

  for c in "${optional_cmds[@]}"; do
    if ! command_exists "$c"; then
      missing+=("$c")
    fi
  done

  if ((${#missing[@]} > 0)); then
    if [[ $SKIP_INSTALL -eq 1 ]]; then
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

  ensure_helper_scripts

  local wallpaper_dir
  wallpaper_dir="$(copy_wallpapers)"

  local has_multi
  has_multi="$(create_multimonitor_layout_if_needed)"

  if [[ $DRY_RUN -ne 1 ]]; then
    backup_file_once "$I3_CONFIG"
  fi

  # Comenta focus parent para dejar libre $mod+a.
  if grep -Eq '^bindsym \$mod\+a[[:space:]]+focus parent' "$I3_CONFIG"; then
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "Se comentaria bindsym \$mod+a focus parent en $I3_CONFIG"
    else
      sed -E -i 's/^bindsym \$mod\+a[[:space:]]+focus parent/#bindsym $mod+a focus parent/' "$I3_CONFIG"
    fi
  fi

  # Reemplaza o agrega launcher rofi en $mod+a.
  if grep -Eq '^bindsym \$mod\+a[[:space:]]+exec .*' "$I3_CONFIG"; then
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "Se actualizaria launcher rofi en \$mod+a dentro de $I3_CONFIG"
    else
      sed -E -i 's|^bindsym \$mod\+a[[:space:]]+exec .*$|bindsym $mod+a exec "~/.config/i3/scripts/i3_rofi_apps"|' "$I3_CONFIG"
    fi
  else
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "Se agregaria launcher rofi en \$mod+a dentro de $I3_CONFIG"
    else
      printf '\n%s\n' 'bindsym $mod+a exec "~/.config/i3/scripts/i3_rofi_apps"' >> "$I3_CONFIG"
    fi
  fi

  # Reemplaza o agrega powermenu en $mod+Shift+e.
  if grep -Eq '^bindsym \$mod\+Shift\+e[[:space:]]+exec .*' "$I3_CONFIG"; then
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "Se actualizaria powermenu en \$mod+Shift+e dentro de $I3_CONFIG"
    else
      sed -E -i 's|^bindsym \$mod\+Shift\+e[[:space:]]+exec .*$|bindsym $mod+Shift+e exec "~/.config/i3/scripts/i3_rofi_powermenu"|' "$I3_CONFIG"
    fi
  else
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "Se agregaria powermenu en \$mod+Shift+e dentro de $I3_CONFIG"
    else
      printf '\n%s\n' 'bindsym $mod+Shift+e exec "~/.config/i3/scripts/i3_rofi_powermenu"' >> "$I3_CONFIG"
    fi
  fi

  # Reemplaza o agrega powermenu en $mod+x.
  if grep -Eq '^bindsym \$mod\+x[[:space:]]+exec .*' "$I3_CONFIG"; then
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "Se actualizaria powermenu en \$mod+x dentro de $I3_CONFIG"
    else
      sed -E -i 's|^bindsym \$mod\+x[[:space:]]+exec .*$|bindsym $mod+x exec "~/.config/i3/scripts/i3_rofi_powermenu"|' "$I3_CONFIG"
    fi
  else
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "Se agregaria powermenu en \$mod+x dentro de $I3_CONFIG"
    else
      printf '\n%s\n' 'bindsym $mod+x exec "~/.config/i3/scripts/i3_rofi_powermenu"' >> "$I3_CONFIG"
    fi
  fi

  # Reemplaza o agrega selector de tema polybar en $mod+Shift+t.
  if grep -Eq '^bindsym \$mod\+Shift\+t[[:space:]]+exec .*' "$I3_CONFIG"; then
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "Se actualizaria selector de tema polybar en \$mod+Shift+t dentro de $I3_CONFIG"
    else
      sed -E -i 's|^bindsym \$mod\+Shift\+t[[:space:]]+exec .*$|bindsym $mod+Shift+t exec "~/.config/i3/scripts/i3_rofi_polybar_theme"|' "$I3_CONFIG"
    fi
  else
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "Se agregaria selector de tema polybar en \$mod+Shift+t dentro de $I3_CONFIG"
    else
      printf '\n%s\n' 'bindsym $mod+Shift+t exec "~/.config/i3/scripts/i3_rofi_polybar_theme"' >> "$I3_CONFIG"
    fi
  fi

  # Ajusta borde general a 0 si existe regla global conocida.
  if grep -Eq '^for_window \[class="\^\.\*"\] border pixel [0-9]+' "$I3_CONFIG"; then
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "Se ajustaria border pixel a 0 para class=^.* en $I3_CONFIG"
    else
      sed -E -i 's/^for_window \[class="\^\.\*"\] border pixel [0-9]+/for_window [class="^.*"] border pixel 0/' "$I3_CONFIG"
    fi
  fi

  update_picom_corner_radius
  update_picom_blur_exclude

  local wallpaper_line="# Configuracion de wallpaper"
  if [[ -n "$wallpaper_dir" ]]; then
    local first_wall
    first_wall="$(find "$wallpaper_dir" -maxdepth 1 -type f | sort | head -n 1 || true)"
    if [[ -n "$first_wall" ]]; then
      wallpaper_line+=$'\n'
      wallpaper_line+="exec --no-startup-id setwallpaper \"${first_wall}\" --mode span"
    fi
  fi

  local multi_line=""
  if [[ "$has_multi" == "1" ]]; then
    multi_line="$(cat <<EOF
# Configuracion de monitor doble
exec --no-startup-id ${SCREENLAYOUT_FILE}
EOF
)"
  fi

  local gap_lines=""
  if [[ "$I3_GAP_SIZE" =~ ^[0-9]+$ ]] && (( I3_GAP_SIZE > 0 )); then
    gap_lines=$(cat <<EOF
# Gap entre ventanas
gaps inner ${I3_GAP_SIZE}
EOF
)
  fi

  local managed_block
  managed_block="$(cat <<EOF
# Configuracion de i3-layouts
${gap_lines}
exec xborders --border-width 2 --border-radius 12 --smart-hide-border
exec i3-layouts

set \$i3l spiral to workspace 1
set \$i3l spiral to workspace 2
set \$i3l spiral to workspace 3
set \$i3l spiral to workspace 4
set \$i3l spiral to workspace 5
set \$i3l spiral to workspace 6
set \$i3l spiral to workspace 7
set \$i3l spiral to workspace 8
set \$i3l spiral to workspace 9
set \$i3l spiral to workspace 0

# Scripts auxiliares
exec --no-startup-id kwalletd6
exec --no-startup-id ${I3_SCRIPTS_DIR}/i3_nzxt
exec --no-startup-id ${I3_SCRIPTS_DIR}/i3_cloud_storage
exec --no-startup-id gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

${multi_line}

${wallpaper_line}
EOF
)"

  append_managed_block "$I3_CONFIG" "$managed_block"

  verify_screenlayout_config_applied "$has_multi"

  update_i3_autostart_if_exists

  finalize_backup_manifest
  if [[ $DRY_RUN -eq 1 ]]; then
    log "Dry-run completado."
  else
    log "Configuracion aplicada correctamente."
  fi
}

main "$@"
