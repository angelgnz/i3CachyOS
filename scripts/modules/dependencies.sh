#!/usr/bin/env bash

OPTIONAL_DEPS=(
  rofi
  picom
  xrandr
  feh
  xborder-git
  i3-layouts
  wallutils
  python
  nextcloud
  kwallet-pam
  polybar-themes-git
  themix-full-git
  mpd
  wal
  sddm
  mousepad
  thunar
  thunar-archive-plugin
)

package_installed() {
  local pkg="$1"

  if command_exists pacman; then
    pacman -Qq "$pkg" >/dev/null 2>&1
  elif command_exists yay; then
    yay -Qq "$pkg" >/dev/null 2>&1
  elif command_exists paru; then
    paru -Qq "$pkg" >/dev/null 2>&1
  else
    return 1
  fi
}

dependency_available() {
  local dep="$1"

  case "$dep" in
    polybar-themes-git|themix-full-git|thunar-archive-plugin|kwallet-pam|pixie-sddm-git)
      package_installed "$dep"
      ;;
    xborder-git|xborders)
      command_exists xborders || package_installed xborder-git
      ;;
    wallutils|setwallpaper)
      command_exists setwallpaper || package_installed wallutils
      ;;
    wal|pywal|python-pywal)
      command_exists wal || package_installed python-pywal || package_installed pywal
      ;;
    i3-layouts)
      command_exists i3-layouts || package_installed i3-layouts
      ;;
    nextcloud|nextcloud-client)
      command_exists nextcloud || package_installed nextcloud-client
      ;;
    python|python3)
      command_exists python || command_exists python3 || package_installed python
      ;;
    *)
      command_exists "$dep" || package_installed "$dep"
      ;;
  esac
}

print_missing_dependencies() {
  local missing=("$@")
  local dep

  if ((${#missing[@]} == 0)); then
    return 0
  fi

  warn "Dependencias opcionales faltantes (${#missing[@]}):"
  for dep in "${missing[@]}"; do
    printf '  - %s\n' "$dep" >&2
  done
}

collect_missing_dependencies() {
  local dep
  local missing=()

  for dep in "$@"; do
    if ! dependency_available "$dep"; then
      missing+=("$dep")
    fi
  done

  if ((${#missing[@]} > 0)); then
    printf '%s\n' "${missing[@]}"
  fi
}

ask_missing_dependency_action() {
  local missing=("$@")
  local choice=""

  printf '\n' >&2
  print_missing_dependencies "${missing[@]}"

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "Modo --dry-run: se simula la opcion 1 (intentar instalar faltantes)."
    echo "1"
    return 0
  fi

  printf 'Elige una acción para las dependencias faltantes:\n' >&2
  printf '  1) Intentar instalar faltantes\n' >&2
  printf '  2) Continuar sin instalar\n' >&2
  printf '  3) Detener script\n' >&2

  if [[ $NON_INTERACTIVE -eq 1 ]]; then
    warn "Modo --yes: se selecciona automáticamente la opción 2 (continuar sin instalar)."
    echo "2"
    return 0
  fi

  while true; do
    printf 'Selecciona una acción [1-3]: ' >&2
    read -r choice
    case "$choice" in
      1)
        warn "Opción seleccionada: 1) Intentar instalar faltantes."
        echo "$choice"
        return 0
        ;;
      2)
        warn "Opción seleccionada: 2) Continuar sin instalar."
        echo "$choice"
        return 0
        ;;
      3)
        warn "Opción seleccionada: 3) Detener script."
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
  local missing=("$@")
  local remaining=()
  local install_failed=0

  if ((${#missing[@]} == 0)); then
    return 0
  fi

  local aur_helper=""
  if command_exists yay; then
    aur_helper="yay"
  elif command_exists paru; then
    aur_helper="paru"
  fi

  local has_pacman=0
  if command_exists pacman; then
    has_pacman=1
  fi

  if [[ -z "$aur_helper" && $has_pacman -eq 0 ]]; then
    err "No se puede instalar automaticamente: no se encontro gestor de paquetes compatible (pacman, yay o paru)."
    return 1
  fi

  local packages=()
  local cmd
  for cmd in "${missing[@]}"; do
    case "$cmd" in
      rofi) packages+=(rofi) ;;
      picom) packages+=(picom) ;;
      xrandr) packages+=(xorg-xrandr) ;;
      feh) packages+=(feh) ;;
      xborders|xborder-git) packages+=(xborder-git) ;;
      i3-layouts) packages+=(i3-layouts) ;;
      setwallpaper|wallutils) packages+=(wallutils) ;;
      nextcloud|nextcloud-client) packages+=(nextcloud-client) ;;
      kwallet-pam) packages+=(kwallet-pam) ;;
      python|python3) packages+=(python) ;;
      wal|pywal|python-pywal) packages+=(python-pywal) ;;
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

  local aur_packages=()
  local official_packages=()
  local has_sync_db=0
  if [[ $has_pacman -eq 1 ]] && compgen -G "/var/lib/pacman/sync/*.db" >/dev/null 2>&1; then
    has_sync_db=1
  fi

  for pkg in "${unique_packages[@]}"; do
    case "$pkg" in
      polybar-themes-git|pixie-sddm-git|themix-full-git|xborder-git|i3-layouts|python-pywal)
        aur_packages+=("$pkg")
        ;;
      *)
        if [[ $has_sync_db -eq 1 ]] && ! pacman -Si "$pkg" >/dev/null 2>&1; then
          aur_packages+=("$pkg")
        else
          official_packages+=("$pkg")
        fi
        ;;
    esac
  done

  log "Intentando instalar: ${unique_packages[*]}"

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "Se instalarian paquetes: ${unique_packages[*]}"
    dry "Modo dry-run: no se realizan instalaciones reales."
    return 0
  fi

  log "Si se solicitan credenciales, responde al prompt en esta misma terminal."

  if ((${#official_packages[@]} > 0)); then
    if [[ -n "$aur_helper" ]]; then
      log "Instalando paquetes oficiales con $aur_helper: ${official_packages[*]}"
      if ! "$aur_helper" -S --needed --noconfirm "${official_packages[@]}"; then
        err "Falló la instalación con $aur_helper para paquetes oficiales."
        install_failed=1
      fi
    elif [[ $has_pacman -eq 1 ]]; then
      log "Instalando paquetes oficiales con sudo pacman: ${official_packages[*]}"
      if ! sudo pacman -S --needed --noconfirm "${official_packages[@]}"; then
        err "Falló la instalación con sudo pacman."
        install_failed=1
      fi
    fi
  fi

  if ((${#aur_packages[@]} > 0)); then
    if [[ -n "$aur_helper" ]]; then
      log "Instalando paquetes AUR con $aur_helper: ${aur_packages[*]}"
      if ! "$aur_helper" -S --needed --noconfirm "${aur_packages[@]}"; then
        err "Falló la instalación de paquetes AUR con $aur_helper."
        install_failed=1
      fi
    else
      err "Faltan paquetes AUR (${aur_packages[*]}) y no se encontro yay/paru para instalarlos automaticamente."
      install_failed=1
    fi
  fi

  mapfile -t remaining < <(collect_missing_dependencies "${missing[@]}")

  if ((${#remaining[@]} == 0)) && [[ $install_failed -eq 0 ]]; then
    log "Dependencias instaladas correctamente."
    return 0
  fi

  if ((${#remaining[@]} > 0)); then
    warn "Después del intento de instalación, aún faltan dependencias:"
    print_missing_dependencies "${remaining[@]}"
  fi

  if [[ $install_failed -ne 0 ]]; then
    err "La instalación automática no se completó correctamente."
  fi

  return 1
}
