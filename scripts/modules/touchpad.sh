#!/usr/bin/env bash

ensure_touchpad_natural_scrolling() {
  local target_dir="/etc/X11/xorg.conf.d"
  local target_file="${target_dir}/30-touchpad.conf"
  local desired_content
  desired_content='Section "InputClass"
    Identifier "touchpad"
    Driver "libinput"
    MatchIsTouchpad "on"
    Option "NaturalScrolling" "True"
EndSection
'

  if ! ensure_sudo_session; then
    return 1
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "Se aseguraria directorio root: $target_dir"
    if [[ -e "$target_file" ]]; then
      dry "Se actualizaria archivo touchpad: $target_file"
      backup_root_file_once "$target_file"
    else
      dry "Se crearia archivo touchpad: $target_file"
      record_new_file "$target_file"
    fi
    return 0
  fi

  local tmp
  tmp="$(mktemp)"
  printf '%s' "$desired_content" > "$tmp"

  if [[ -e "$target_file" ]]; then
    backup_root_file_once "$target_file"
    if sudo cmp -s "$tmp" "$target_file"; then
      rm -f "$tmp"
      log "Touchpad natural scrolling ya estaba configurado en: $target_file"
      return 0
    fi
  else
    record_new_file "$target_file"
  fi

  if sudo install -d -m 755 "$target_dir" && sudo install -Dm644 "$tmp" "$target_file"; then
    log "Touchpad natural scrolling configurado en: $target_file"
  else
    warn "No se pudo configurar touchpad natural scrolling en: $target_file"
  fi

  rm -f "$tmp"
}

command_touchpad_config() {
  ensure_touchpad_natural_scrolling
}
