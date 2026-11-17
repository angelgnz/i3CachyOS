#!/usr/bin/env bash

disable_conflicting_display_managers() {
  local target_service="${1:-sddm.service}"
  local known_dm_services=(
    ly.service
    sddm.service
    lightdm.service
    gdm.service
    lxdm.service
    xdm.service
  )
  local svc
  local enabled=0
  local active=0

  for svc in "${known_dm_services[@]}"; do
    if [[ "$svc" == "$target_service" ]]; then
      continue
    fi

    if sudo systemctl is-enabled "$svc" >/dev/null 2>&1; then
      enabled=1
    else
      enabled=0
    fi

    if sudo systemctl is-active "$svc" >/dev/null 2>&1; then
      active=1
    else
      active=0
    fi

    if [[ $enabled -eq 1 || $active -eq 1 ]]; then
      log "Desactivando display manager en conflicto: $svc"
      if ! sudo systemctl disable --now "$svc"; then
        warn "No se pudo desactivar completamente: $svc"
      fi
    fi
  done
}

_sddm_render_theme_config() {
  awk '
    BEGIN { in_theme=0; theme_found=0; current_written=0 }
    function ensure_current() {
      if (theme_found && !current_written) {
        print "Current=pixie"
        current_written=1
      }
    }
    /^\[Theme\][[:space:]]*$/ {
      if (in_theme) {
        ensure_current()
      }
      in_theme=1
      theme_found=1
      current_written=0
      print
      next
    }
    in_theme && /^\[/ {
      ensure_current()
      in_theme=0
    }
    in_theme && /^[[:space:]]*Current[[:space:]]*=/ {
      print "Current=pixie"
      current_written=1
      next
    }
    { print }
    END {
      if (in_theme) {
        ensure_current()
      }
      if (!theme_found) {
        if (NR > 0) {
          print ""
        }
        print "[Theme]"
        print "Current=pixie"
      }
    }
  '
}

ensure_sddm_theme_config() {
  local target="/etc/sddm.conf"
  local tmp=""
  local can_compare=0

  tmp="$(mktemp)"

  if [[ -e "$target" ]]; then
    if [[ -r "$target" ]]; then
      can_compare=1
      _sddm_render_theme_config < "$target" > "$tmp"
    elif [[ $DRY_RUN -ne 1 ]]; then
      can_compare=1
      sudo cat "$target" | _sddm_render_theme_config > "$tmp"
    fi
  else
    cat > "$tmp" <<'EOF'
[Theme]
Current=pixie
EOF
  fi

  if [[ -e "$target" && $can_compare -eq 1 ]]; then
    if [[ -r "$target" ]]; then
      if cmp -s "$tmp" "$target"; then
        rm -f "$tmp"
        log "Tema SDDM ya estaba configurado: pixie"
        return 0
      fi
    elif [[ $DRY_RUN -ne 1 ]] && sudo cmp -s "$tmp" "$target"; then
      rm -f "$tmp"
      log "Tema SDDM ya estaba configurado: pixie"
      return 0
    fi
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    if [[ -e "$target" ]]; then
      dry "Se estableceria tema SDDM en: $target"
      backup_root_file_once "$target"
    else
      dry "Se crearia archivo SDDM: $target"
      record_new_file "$target"
    fi
    rm -f "$tmp"
    return 0
  fi

  if [[ -e "$target" ]]; then
    backup_root_file_once "$target"
  else
    record_new_file "$target"
  fi

  if sudo install -Dm644 "$tmp" "$target"; then
    log "Tema SDDM configurado: pixie"
  else
    warn "No se pudo configurar el tema SDDM en: $target"
  fi

  rm -f "$tmp"
}

_install_pixie_asset() {
  local src="$1"
  local dst="$2"
  local label="$3"
  local matches=0

  if [[ -e "$dst" ]]; then
    if [[ -r "$dst" ]] && cmp -s "$src" "$dst"; then
      matches=1
    elif [[ $DRY_RUN -ne 1 ]] && sudo cmp -s "$src" "$dst"; then
      matches=1
    fi
  fi

  if [[ $matches -eq 1 ]]; then
    log "${label} ya estaba actualizado: $dst"
    return 0
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "Se reemplazaria ${label}: $dst con $src"
    if [[ -e "$dst" ]]; then
      backup_root_file_once "$dst"
    else
      record_new_file "$dst"
    fi
    return 0
  fi

  if [[ -e "$dst" ]]; then
    backup_root_file_once "$dst"
  else
    record_new_file "$dst"
  fi

  if sudo install -Dm644 "$src" "$dst"; then
    log "${label} actualizado: $dst"
  else
    warn "No se pudo actualizar ${label}: $dst"
  fi
}

replace_pixie_background() {
  local pixie_dir="/usr/share/sddm/themes/pixie"
  local pixie_assets_dir="${pixie_dir}/assets"
  local pixie_background="${pixie_assets_dir}/background.jpg"
  local pixie_avatar="${pixie_assets_dir}/avatar.jpg"
  local city_source="${REPO_ROOT}/wallpapers/city.jpg"
  local avatar_repo_dir="${REPO_ROOT}/avatar"
  local avatar_source=""
  local candidate

  if [[ ! -d "$pixie_assets_dir" ]]; then
    warn "No existe tema Pixie en: $pixie_assets_dir"
    return 0
  fi

  if [[ -d "$avatar_repo_dir" ]]; then
    shopt -s nullglob
    for candidate in "$avatar_repo_dir"/*; do
      if [[ ! -f "$candidate" ]]; then
        continue
      fi
      case "${candidate,,}" in
        *.jpg|*.jpeg|*.png|*.webp)
          avatar_source="$candidate"
          break
          ;;
      esac
    done
    shopt -u nullglob
  fi

  if [[ ! -f "$city_source" ]]; then
    warn "No se encontro city.jpg en el repo: $city_source"
  else
    _install_pixie_asset "$city_source" "$pixie_background" "Fondo Pixie"
  fi

  if [[ -z "$avatar_source" ]]; then
    log "No se encontro imagen en ${avatar_repo_dir}; se mantiene avatar actual de Pixie."
    return 0
  fi

  _install_pixie_asset "$avatar_source" "$pixie_avatar" "Avatar Pixie"
}

command_display_manager() {
  local target_dm_pkg="sddm"
  local target_dm_service="sddm.service"

  if ! ensure_sudo_session; then
    return 1
  fi

  if [[ $SKIP_INSTALL -eq 1 ]]; then
    warn "Se omite instalación de $target_dm_pkg por --skip-install"
  else
    if ! install_missing_dependencies "$target_dm_pkg"; then
      err "No se pudo instalar $target_dm_pkg."
      return 1
    fi
    log "Instalando tema SDDM: pixie-sddm-git"
    if ! install_missing_dependencies "pixie-sddm-git"; then
      warn "No se pudo instalar pixie-sddm-git. Continuando sin tema SDDM."
    fi
  fi

  ensure_sddm_theme_config
  replace_pixie_background

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "Se deshabilitarian display managers en conflicto y se habilitaria $target_dm_service"
    dry "Se instalarian: $target_dm_pkg pixie-sddm-git"
    return 0
  fi

  disable_conflicting_display_managers "$target_dm_service"

  log "Habilitando display manager objetivo: $target_dm_service"
  if ! sudo systemctl enable "$target_dm_service"; then
    err "No se pudo habilitar $target_dm_service"
    return 1
  fi

  log "Display manager configurado: $target_dm_service"
}
