#!/usr/bin/env bash

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

ensure_xfce4_helpers_terminal() {
  local xfce4_dir="${XDG_CONFIG_HOME:-$HOME/.config}/xfce4"
  local helpers_rc="${xfce4_dir}/helpers.rc"

  if [[ -f "$helpers_rc" ]]; then
    return 0
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "Se crearia archivo XFCE helpers: $helpers_rc"
    return 0
  fi

  mkdir -p "$xfce4_dir"
  record_new_file "$helpers_rc"
  printf 'TerminalEmulator=alacritty\n' > "$helpers_rc"
  log "Creado archivo XFCE helpers: $helpers_rc"
}
