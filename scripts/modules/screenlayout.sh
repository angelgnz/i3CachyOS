#!/usr/bin/env bash

verify_screenlayout_config_applied() {
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

create_multimonitor_layout_if_needed() {
  if ! command_exists xrandr; then
    warn "xrandr no esta disponible. Se omite auto layout de pantallas."
    echo "0"
    return 0
  fi

  local xrandr_out
  if ! xrandr_out="$(xrandr --query 2>/dev/null)"; then
    warn "No se pudo consultar xrandr. Se omite auto layout de pantallas."
    echo "0"
    return 0
  fi

  mapfile -t connected < <(printf '%s\n' "$xrandr_out" | awk '/ connected/{print $1}')

  if ((${#connected[@]} < 1)); then
    warn "No se detectaron monitores conectados en xrandr."
    echo "0"
    return 0
  fi

  mapfile -t disconnected_active < <(printf '%s\n' "$xrandr_out" | awk '/ disconnected/ && /[0-9]+x[0-9]+\+[0-9]+\+[0-9]+/{print $1}')

  local monitor_specs=()
  local primary_mon=""
  local primary_mode=""
  local primary_rate=""
  local primary_width=0
  local primary_area=0
  local mon

  for mon in "${connected[@]}"; do
    local mode=""
    local rate=""
    read -r mode rate < <(printf '%s\n' "$xrandr_out" | awk -v m="$mon" '
      $1 == m && $2 == "connected" {inside=1; next}
      inside && /^[^[:space:]]/ {inside=0}
      inside && $1 ~ /^[0-9]+x[0-9]+$/ {
        mode = $1
        max_r = ""
        max_val = 0
        for (i = 2; i <= NF; i++) {
          tok = $i
          gsub(/[*+]/, "", tok)
          if (tok ~ /^[0-9]+(\.[0-9]+)?$/) {
            val = tok + 0
            if (val > max_val) {
              max_val = val
              max_r = tok
            }
          }
        }
        sub(/\.0+$/, "", max_r)
        print mode, max_r
        exit
      }
    ') || true

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

    monitor_specs+=("${width}|${mon}|${mode}|${rate}")

    if (( area > primary_area )); then
      primary_area=$area
      primary_mon="$mon"
      primary_mode="$mode"
      primary_rate="$rate"
      primary_width=$width
    fi
  done

  local cmd_lines=()
  local x_pos=0
  local ordered_specs=()
  local off_mon

  for off_mon in "${disconnected_active[@]}"; do
    cmd_lines+=("       --output ${off_mon} --off \\")
  done

  while IFS='|' read -r width mon mode rate; do
    if [[ "$mon" != "$primary_mon" ]]; then
      ordered_specs+=("${width}|${mon}|${mode}|${rate}")
    fi
  done < <(printf '%s\n' "${monitor_specs[@]}" | sort -s -n -t '|' -k1,1)

  ordered_specs+=("${primary_width}|${primary_mon}|${primary_mode}|${primary_rate}")

  while IFS='|' read -r width mon mode rate; do
    local rate_arg=""
    if [[ -n "$rate" ]]; then
      rate_arg=" --rate ${rate}"
    fi

    if [[ "$mon" == "$primary_mon" ]]; then
      cmd_lines+=("       --output ${mon} --primary --mode ${mode}${rate_arg} --pos ${x_pos}x0 --rotate normal \\")
    else
      cmd_lines+=("       --output ${mon} --mode ${mode}${rate_arg} --pos ${x_pos}x0 --rotate normal \\")
    fi

    x_pos=$((x_pos + width))
  done < <(printf '%s\n' "${ordered_specs[@]}")

  if ((${#cmd_lines[@]} > 0)); then
    local last_index
    last_index=$((${#cmd_lines[@]} - 1))
    cmd_lines[$last_index]="${cmd_lines[$last_index]% \\}"
  fi

  local layout_label="multimonitor"
  if ((${#connected[@]} == 1)); then
    layout_label="de pantalla unica"
  fi

  local tmp
  tmp="$(mktemp)"
  {
    echo '#!/usr/bin/env bash'
    echo 'set -euo pipefail'
    echo
    echo "xrandr \\"
    printf '%s\n' "${cmd_lines[@]}"
    echo
    echo 'echo "Configuracion de pantallas aplicada automaticamente"'
    echo
    echo "if [[ -x \"${I3_SCRIPTS_DIR}/i3_wallpaper\" ]]; then"
    echo "  \"${I3_SCRIPTS_DIR}/i3_wallpaper\""
    echo "fi"
  } > "$tmp"

  if [[ -f "$SCREENLAYOUT_FILE" ]] && cmp -s "$SCREENLAYOUT_FILE" "$tmp" && [[ -x "$SCREENLAYOUT_FILE" ]]; then
    rm -f "$tmp"
    log "Layout ${layout_label} ya estaba actualizado: $SCREENLAYOUT_FILE"
    echo "1"
    return 0
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "Se aseguraria directorio: $SCREENLAYOUT_DIR"
    if [[ -f "$SCREENLAYOUT_FILE" ]]; then
      dry "Se respaldaria archivo: $SCREENLAYOUT_FILE"
    else
      dry "Se crearia archivo: $SCREENLAYOUT_FILE"
    fi
    dry "Se generaria layout ${layout_label} en: $SCREENLAYOUT_FILE"
    rm -f "$tmp"
    echo "1"
    return 0
  fi

  mkdir -p "$SCREENLAYOUT_DIR"
  if [[ -f "$SCREENLAYOUT_FILE" ]]; then
    backup_file_once "$SCREENLAYOUT_FILE"
  else
    record_new_file "$SCREENLAYOUT_FILE"
  fi

  cat "$tmp" > "$SCREENLAYOUT_FILE"
  chmod +x "$SCREENLAYOUT_FILE"
  rm -f "$tmp"
  log "Generado layout ${layout_label}: $SCREENLAYOUT_FILE"
  echo "1"
}
