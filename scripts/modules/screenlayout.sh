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

is_laptop_system() {
  if [[ -r /sys/class/dmi/id/chassis_type ]]; then
    local chassis
    chassis="$(< /sys/class/dmi/id/chassis_type)"
    case "$chassis" in
      8|9|10|11|14|31|32) return 0 ;;
    esac
  fi

  if compgen -G "/sys/class/power_supply/BAT*" >/dev/null; then
    return 0
  fi

  return 1
}

is_laptop_monitor() {
  local mon="$1"
  if [[ "$mon" =~ ^(eDP|LVDS|DSI) ]]; then
    return 0
  fi
  if is_laptop_system && [[ "$mon" =~ (eDP|LVDS|DSI) ]]; then
    return 0
  fi
  return 1
}

get_monitor_details() {
  local mon="$1"
  xrandr --query | awk -v m="$mon" '
    $1 == m && $2 == "connected" {
      inside=1
      if (match($0, /([0-9]+)mm x ([0-9]+)mm/, sz)) {
        w_mm = sz[1]
        h_mm = sz[2]
      } else {
        w_mm = 0
        h_mm = 0
      }
      next
    }
    inside && /^[ ]+[0-9]+x[0-9]+/ {
      if (!mode) mode = $1
      if ($0 ~ /\+/) {
        print mode, (w_mm ? w_mm : 0), (h_mm ? h_mm : 0)
        printed=1
        exit
      }
    }
    inside && NF == 0 {
      if (!printed && mode) {
        print mode, (w_mm ? w_mm : 0), (h_mm ? h_mm : 0)
        printed=1
        exit
      }
      inside=0
    }
    END {
      if (!printed && mode) {
        print mode, (w_mm ? w_mm : 0), (h_mm ? h_mm : 0)
      }
    }
  '
}

calculate_laptop_scale() {
  local width="$1"
  local height="$2"
  local width_mm="${3:-0}"
  local height_mm="${4:-0}"
  local requested_scale="${LAPTOP_SCALE:-auto}"

  local dpi=0
  if (( width_mm > 0 )); then
    dpi=$(( (width * 254 + width_mm * 5) / (width_mm * 10) ))
  fi

  local scale_ui="1.0"
  if [[ -n "$requested_scale" && "$requested_scale" != "auto" ]]; then
    scale_ui="$requested_scale"
  else
    if (( dpi >= 220 )); then
      scale_ui="1.5"
    elif (( dpi >= 165 )); then
      scale_ui="1.25"
    elif (( dpi >= 140 )); then
      scale_ui="1.25"
    elif (( dpi == 0 && (width >= 2560 || height >= 1440) )); then
      scale_ui="1.25"
    else
      scale_ui="1.0"
    fi
  fi

  awk -v w="$width" -v h="$height" -v s="$scale_ui" -v d="$dpi" '
    BEGIN {
      if (s ~ /^[0-9]+(\.[0-9]+)?$/ && s > 0) {
        if (s < 1.0 && s >= 0.3) {
          factor = s + 0.0
          ui_scale = 1.0 / factor
        } else {
          ui_scale = s + 0.0
          factor = 1.0 / ui_scale
        }
      } else {
        factor = 1.0
        ui_scale = 1.0
      }

      factor_str = sprintf("%.4f", factor)
      sub(/\.?0+$/, "", factor_str)
      if (factor_str == "") factor_str = "1"

      ui_str = sprintf("%.2f", ui_scale)
      sub(/\.?0+$/, "", ui_str)

      lw = int(w * factor + 0.5)
      lh = int(h * factor + 0.5)

      printf "%sx%s %d %d %s %d\n", factor_str, factor_str, lw, lh, ui_str, d
    }
  '
}

create_multimonitor_layout_if_needed() {
  if ! command_exists xrandr; then
    warn "xrandr no esta disponible. Se omite configuracion de pantalla."
    return 0
  fi

  mapfile -t connected < <(xrandr --query | awk '/ connected/{print $1}')

  if ((${#connected[@]} == 0)); then
    warn "No se detectaron pantallas conectadas."
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
  local primary_spec=""
  local primary_area=0
  local mon

  for mon in "${connected[@]}"; do
    local mode="" width_mm=0 height_mm=0
    read -r mode width_mm height_mm < <(get_monitor_details "$mon")

    if [[ -z "$mode" ]]; then
      mode="1920x1080"
    fi

    local width="${mode%x*}"
    local height="${mode#*x}"

    if ! [[ "$width" =~ ^[0-9]+$ && "$height" =~ ^[0-9]+$ ]]; then
      width=1920
      height=1080
    fi

    local scale_xr="1x1"
    local log_w="$width"
    local log_h="$height"
    local scale_ui="1.0"
    local dpi=0

    if is_laptop_monitor "$mon"; then
      read -r scale_xr log_w log_h scale_ui dpi < <(calculate_laptop_scale "$width" "$height" "$width_mm" "$height_mm")
      if [[ "$scale_xr" != "1x1" ]]; then
        log "Monitor de laptop detectado: ${mon} (${mode}, DPI: ${dpi}, escala visual: ${scale_ui}x, xrandr: ${scale_xr}, resolucion logica: ${log_w}x${log_h})"
      else
        log "Monitor de laptop detectado: ${mon} (${mode}, DPI: ${dpi}, escala: 1.0x)"
      fi
    else
      log "Monitor externo detectado: ${mon} (${mode}, sin escalado)"
    fi

    local area=$((width * height))
    monitor_specs+=("${log_w}|${mon}|${mode}|${scale_xr}|${log_h}")

    if (( area > primary_area )) || [[ -z "$primary_mon" ]]; then
      primary_area=$area
      primary_mon="$mon"
      primary_spec="${log_w}|${mon}|${mode}|${scale_xr}|${log_h}|1"
    fi
  done

  local ordered_specs=()
  if ((${#connected[@]} == 1)); then
    ordered_specs+=("${primary_spec}")
  else
    while IFS='|' read -r log_w mon mode scale_xr log_h; do
      if [[ "$mon" != "$primary_mon" ]]; then
        ordered_specs+=("${log_w}|${mon}|${mode}|${scale_xr}|${log_h}|0")
      fi
    done < <(printf '%s\n' "${monitor_specs[@]}" | sort -s -n -t '|' -k1,1)

    ordered_specs+=("${primary_spec}")
  fi

  local cmd_lines=()
  local x_pos=0

  for spec in "${ordered_specs[@]}"; do
    local log_w mon mode scale_xr log_h is_prim
    IFS='|' read -r log_w mon mode scale_xr log_h is_prim <<< "$spec"

    local line="       --output ${mon}"
    if [[ "$is_prim" -eq 1 ]]; then
      line+=" --primary"
    fi
    line+=" --mode ${mode} --pos ${x_pos}x0 --rotate normal"

    if [[ "$scale_xr" != "1x1" ]]; then
      line+=" --scale ${scale_xr} --panning ${log_w}x${log_h}+${x_pos}+0"
    fi
    line+=" \\"

    cmd_lines+=("$line")
    x_pos=$((x_pos + log_w))
  done

  if ((${#cmd_lines[@]} > 0)); then
    local last_index=$((${#cmd_lines[@]} - 1))
    cmd_lines[$last_index]="${cmd_lines[$last_index]% \\}"
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "Se generaria layout de pantalla en: $SCREENLAYOUT_FILE"
    dry "Comando xrandr propuesto:"
    dry "xrandr \\"
    local cl
    for cl in "${cmd_lines[@]}"; do
      dry "$cl"
    done
  else
    {
      echo '#!/usr/bin/env bash'
      echo 'set -euo pipefail'
      echo
      echo 'xrandr \'
      printf '%s\n' "${cmd_lines[@]}"
      echo
      echo 'echo "Configuracion de pantalla aplicada correctamente"'
    } > "$SCREENLAYOUT_FILE"

    chmod +x "$SCREENLAYOUT_FILE"
    log "Generado layout de pantalla: $SCREENLAYOUT_FILE"
  fi
}
