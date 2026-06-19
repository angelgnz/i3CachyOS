#!/usr/bin/env bash

ensure_polybar_shapes_tray_module() {
  local target="$POLYBAR_SHAPES_MODULES_FILE"
  local marker="[module/tray]"
  local block
  block="$(cat <<'EOF'
[module/tray]
type = internal/tray
tray-spacing = 8px
tray-background = ${color.shade7}
format-background = ${color.shade7}

;; _-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_
EOF
)"

  if [[ -f "$target" ]] && grep -Fq "$marker" "$target"; then
    log "Modulo tray ya presente en: $target"
    return 0
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "Se agregaria modulo tray al final de: $target"
    return 0
  fi

  if [[ -f "$target" ]]; then
    backup_file_once "$target"
  else
    record_new_file "$target"
    mkdir -p "$(dirname "$target")"
    : > "$target"
  fi

  if [[ -s "$target" ]]; then
    printf '\n%s\n' "$block" >> "$target"
  else
    printf '%s\n' "$block" >> "$target"
  fi

  log "Agregado modulo tray en: $target"
}

ensure_polybar_shapes_modules_right_tray() {
  local target="$POLYBAR_SHAPES_CONFIG_FILE"

  if [[ ! -f "$target" ]]; then
    warn "No existe config.ini de polybar shapes: $target"
    return 0
  fi

  if grep -Eq '^modules-right[[:space:]]*=.*\btray\b' "$target" \
    && ! grep -Eq '^modules-right[[:space:]]*=.*\bcolor-switch\b' "$target"; then
    log "modules-right ya usa tray en: $target"
    return 0
  fi

  if ! grep -Eq '^modules-right[[:space:]]*=.*\bcolor-switch\b' "$target"; then
    warn "No se encontro color-switch en modules-right dentro de: $target"
    return 0
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "Se reemplazaria color-switch por tray en modules-right de: $target"
    return 0
  fi

  backup_file_once "$target"
  sed -E -i '/^modules-right[[:space:]]*=/ s/\bcolor-switch\b/tray/g' "$target"
  log "Reemplazado color-switch por tray en modules-right: $target"
}
