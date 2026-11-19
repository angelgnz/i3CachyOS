#!/usr/bin/env bash

verify_screenlayout_config_applied() {
  local expected_line="exec --no-startup-id ${SCREENLAYOUT_FILE}"
  local expected_watch_line="exec_always --no-startup-id ${SCREENLAYOUT_FILE} --watch"

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

  if grep -Fq "$expected_watch_line" "$I3_CONFIG"; then
    log "Watcher hot-plug de monitores configurado en i3 config: ${SCREENLAYOUT_FILE} --watch"
  else
    warn "No se encontro watcher hot-plug de monitores en: $I3_CONFIG (ejecuta i3-patch para agregarlo)."
  fi
}

create_multimonitor_layout_if_needed() {
  ensure_helper_script "i3_screenlayout"

  local xrandr_ready=0
  if command_exists xrandr && xrandr --query >/dev/null 2>&1; then
    xrandr_ready=1
  fi

  if [[ $xrandr_ready -eq 1 ]]; then
    "${SCRIPT_DIR}/apps/i3_screenlayout" --dry-run --laptop-scale "${LAPTOP_SCALE}" || true
  else
    warn "xrandr no esta disponible o no hay sesion X11 activa; se generara layout dinamico igualmente."
  fi

  local tmp
  tmp="$(mktemp)"
  {
    echo '#!/usr/bin/env bash'
    echo 'set -euo pipefail'
    echo
    printf 'DEFAULT_LAPTOP_SCALE=%q\n' "$LAPTOP_SCALE"
    echo 'export LAPTOP_SCALE="${LAPTOP_SCALE:-$DEFAULT_LAPTOP_SCALE}"'
    echo
    printf 'I3_SCREENLAYOUT_BIN=%q\n' "${I3_SCRIPTS_DIR}/i3_screenlayout"
    echo 'if [[ -x "$I3_SCREENLAYOUT_BIN" ]]; then'
    echo '  exec "$I3_SCREENLAYOUT_BIN" "$@"'
    echo 'fi'
    echo
    echo 'echo "[ERROR] No se encontro helper ejecutable: $I3_SCREENLAYOUT_BIN" >&2'
    echo 'exit 1'
  } > "$tmp"

  if [[ -f "$SCREENLAYOUT_FILE" ]] && cmp -s "$SCREENLAYOUT_FILE" "$tmp" && [[ -x "$SCREENLAYOUT_FILE" ]]; then
    rm -f "$tmp"
    log "Layout dinamico ya estaba actualizado: $SCREENLAYOUT_FILE"
  elif [[ $DRY_RUN -eq 1 ]]; then
    dry "Se aseguraria directorio: $SCREENLAYOUT_DIR"
    if [[ -f "$SCREENLAYOUT_FILE" ]]; then
      dry "Se respaldaria archivo: $SCREENLAYOUT_FILE"
    else
      dry "Se crearia archivo: $SCREENLAYOUT_FILE"
    fi
    dry "Se generaria layout dinamico en: $SCREENLAYOUT_FILE"
    rm -f "$tmp"
  else
    mkdir -p "$SCREENLAYOUT_DIR"
    if [[ -f "$SCREENLAYOUT_FILE" ]]; then
      backup_file_once "$SCREENLAYOUT_FILE"
    else
      record_new_file "$SCREENLAYOUT_FILE"
    fi

    cat "$tmp" > "$SCREENLAYOUT_FILE"
    chmod +x "$SCREENLAYOUT_FILE"
    rm -f "$tmp"
    log "Generado layout dinamico: $SCREENLAYOUT_FILE"
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "Se aplicaria layout dinamico de pantalla: $SCREENLAYOUT_FILE"
  elif [[ $xrandr_ready -eq 1 ]]; then
    "$SCREENLAYOUT_FILE" || warn "No se pudo aplicar el layout de pantalla en esta sesion."
  fi
}
