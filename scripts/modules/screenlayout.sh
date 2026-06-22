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
      echo "xrandr \\"
      printf '%s\n' "${cmd_lines[@]}"
      echo
      echo 'echo "Configuracion multimonitor aplicada automaticamente"'
    } > "$SCREENLAYOUT_FILE"

    chmod +x "$SCREENLAYOUT_FILE"
    log "Generado layout multimonitor: $SCREENLAYOUT_FILE"
  fi
  echo "1"
}
