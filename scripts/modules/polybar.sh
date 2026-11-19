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

ensure_polybar_current_theme() {
  local polybar_dir="${POLYBAR_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/polybar}"
  local target="${polybar_dir}/.current_theme"

  if [[ -f "$target" ]]; then
    return 0
  fi

  if [[ ! -d "$polybar_dir" ]]; then
    return 0
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "Se inicializaria tema actual de Polybar (shapes) en: $target"
    return 0
  fi

  record_new_file "$target"
  printf '%s\n' "shapes" > "$target"
  log "Tema actual de Polybar inicializado en: $target (shapes)"
}

_read_trimmed_sysfs_attr() {
  local file="$1"
  [[ -r "$file" ]] || return 1

  local val
  val="$(< "$file")"
  val="${val//$'\r'/}"
  val="${val//$'\n'/}"
  val="${val#"${val%%[![:space:]]*}"}"
  val="${val%"${val##*[![:space:]]}"}"
  printf '%s' "$val"
}

_list_power_supply_entries() {
  local ps_dir="$1"
  local entries=()
  local prev_nullglob=0

  shopt -q nullglob && prev_nullglob=1
  shopt -s nullglob
  entries=("$ps_dir"/*)
  if [[ $prev_nullglob -eq 0 ]]; then
    shopt -u nullglob
  fi

  if ((${#entries[@]} > 0)); then
    printf '%s\n' "${entries[@]}" | LC_ALL=C sort
  fi
}

detect_system_battery() {
  local ps_dir="${POWER_SUPPLY_DIR:-/sys/class/power_supply}"
  [[ -d "$ps_dir" ]] || return 1

  local bat_preferred=()
  local bat_other=()
  local entry
  local name
  local type_val
  local scope_val
  local present_val

  while IFS= read -r entry; do
    [[ -n "$entry" && -d "$entry" ]] || continue
    name="${entry##*/}"

    case "$name" in
      hidpp_*|hid-*|wacom_*|sony_controller_*|ps-controller-*)
        continue
        ;;
    esac

    type_val="$(_read_trimmed_sysfs_attr "${entry}/type" || true)"
    [[ "$type_val" == "Battery" ]] || continue

    if [[ -r "${entry}/scope" ]]; then
      scope_val="$(_read_trimmed_sysfs_attr "${entry}/scope" || true)"
      if [[ -n "$scope_val" && "$scope_val" != "System" ]]; then
        continue
      fi
    fi

    if [[ -r "${entry}/present" ]]; then
      present_val="$(_read_trimmed_sysfs_attr "${entry}/present" || true)"
      if [[ "$present_val" == "0" ]]; then
        continue
      fi
    fi

    if [[ ! -r "${entry}/capacity" && ! -r "${entry}/status" && ! -r "${entry}/energy_now" && ! -r "${entry}/charge_now" ]]; then
      continue
    fi

    if [[ "$name" =~ ^BAT ]]; then
      bat_preferred+=("$name")
    else
      bat_other+=("$name")
    fi
  done < <(_list_power_supply_entries "$ps_dir")

  if ((${#bat_preferred[@]} > 0)); then
    printf '%s\n' "${bat_preferred[0]}"
    return 0
  fi

  if ((${#bat_other[@]} > 0)); then
    printf '%s\n' "${bat_other[0]}"
    return 0
  fi

  return 1
}

detect_power_adapter() {
  local ps_dir="${POWER_SUPPLY_DIR:-/sys/class/power_supply}"
  [[ -d "$ps_dir" ]] || return 1

  local mains_preferred=()
  local mains_other=()
  local usb_fallback=()
  local entry
  local name
  local type_val
  local scope_val

  while IFS= read -r entry; do
    [[ -n "$entry" && -d "$entry" ]] || continue
    name="${entry##*/}"

    if [[ -r "${entry}/scope" ]]; then
      scope_val="$(_read_trimmed_sysfs_attr "${entry}/scope" || true)"
      if [[ -n "$scope_val" && "$scope_val" != "System" ]]; then
        continue
      fi
    fi

    type_val="$(_read_trimmed_sysfs_attr "${entry}/type" || true)"
    if [[ "$type_val" == "Mains" ]]; then
      if [[ "$name" =~ ^(AC|ACAD|ADP) ]]; then
        mains_preferred+=("$name")
      else
        mains_other+=("$name")
      fi
    elif [[ "$type_val" =~ ^(USB|USB_PD|USB_C|USB_DCP)$ && -r "${entry}/online" ]]; then
      usb_fallback+=("$name")
    fi
  done < <(_list_power_supply_entries "$ps_dir")

  if ((${#mains_preferred[@]} > 0)); then
    printf '%s\n' "${mains_preferred[0]}"
    return 0
  fi

  if ((${#mains_other[@]} > 0)); then
    printf '%s\n' "${mains_other[0]}"
    return 0
  fi

  if ((${#usb_fallback[@]} > 0)); then
    printf '%s\n' "${usb_fallback[0]}"
    return 0
  fi

  return 1
}

_update_polybar_ini_battery_fields() {
  local target="$1"
  local bat_name="$2"
  local adapter_name="$3"

  if [[ ! -f "$target" || -z "$bat_name" ]]; then
    return 0
  fi

  local tmp
  tmp="$(mktemp)"

  awk -v bat="$bat_name" -v adapter="$adapter_name" '
    function flush_section(    i, is_bat, seen_bat, seen_adapter, type_idx, indent, line) {
      if (sec_len == 0) {
        return
      }

      is_bat = 0
      seen_bat = 0
      seen_adapter = 0
      type_idx = 0

      for (i = 1; i <= sec_len; i++) {
        line = sec_lines[i]
        if (line ~ /^[[:space:]]*type[[:space:]]*=[[:space:]]*internal\/battery[[:space:]]*$/) {
          is_bat = 1
          type_idx = i
        } else if (line ~ /^[[:space:]]*battery[[:space:]]*=/) {
          seen_bat = 1
        } else if (line ~ /^[[:space:]]*adapter[[:space:]]*=/) {
          seen_adapter = 1
        }
      }

      for (i = 1; i <= sec_len; i++) {
        line = sec_lines[i]
        if (is_bat) {
          if (line ~ /^[[:space:]]*battery[[:space:]]*=/) {
            match(line, /^[[:space:]]*/)
            indent = substr(line, 1, RLENGTH)
            print indent "battery = " bat
            continue
          }
          if (adapter != "" && line ~ /^[[:space:]]*adapter[[:space:]]*=/) {
            match(line, /^[[:space:]]*/)
            indent = substr(line, 1, RLENGTH)
            print indent "adapter = " adapter
            continue
          }
        }

        print line

        if (is_bat && i == type_idx) {
          match(line, /^[[:space:]]*/)
          indent = substr(line, 1, RLENGTH)
          if (!seen_bat) {
            print indent "battery = " bat
          }
          if (adapter != "" && !seen_adapter) {
            print indent "adapter = " adapter
          }
        }
      }

      sec_len = 0
    }

    /^[[:space:]]*\[[^]]+\]/ {
      flush_section()
      in_section = 1
      sec_lines[++sec_len] = $0
      next
    }

    {
      if (!in_section) {
        print $0
      } else {
        sec_lines[++sec_len] = $0
      }
    }

    END {
      flush_section()
    }
  ' "$target" > "$tmp"

  if cmp -s "$target" "$tmp"; then
    rm -f "$tmp"
    return 0
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "Se actualizaria modulo battery (${bat_name}${adapter_name:+ / $adapter_name}) en: $target"
    rm -f "$tmp"
    return 0
  fi

  backup_file_once "$target"
  cat "$tmp" > "$target"
  rm -f "$tmp"
  log "Actualizado modulo battery (${bat_name}${adapter_name:+ / $adapter_name}) en: $target"
}

_ensure_polybar_shapes_battery_definition() {
  local bat_name="$1"
  local adapter_name="$2"
  local target="$POLYBAR_SHAPES_MODULES_FILE"

  if [[ -f "$target" ]] && grep -Eq '^[[:space:]]*\[module/battery\]' "$target"; then
    return 0
  fi

  local adapter_line=""
  if [[ -n "$adapter_name" ]]; then
    adapter_line="adapter = ${adapter_name}"$'\n'
  fi

  local block
  block="$(cat <<EOF
[module/battery]
type = internal/battery
full-at = 99
battery = ${bat_name}
${adapter_line}poll-interval = 2
time-format = %H:%M

format-charging = <animation-charging> <label-charging>
format-charging-background = \${color.shade4}
format-charging-padding = 1

format-discharging = <ramp-capacity> <label-discharging>
format-discharging-background = \${color.shade4}
format-discharging-padding = 1

format-full = <label-full>
format-full-prefix = 
format-full-background = \${color.shade4}
format-full-padding = 1

label-charging = "%percentage%% "
label-discharging = "%percentage%% "
label-full = " Full "

ramp-capacity-0 = 
ramp-capacity-1 = 
ramp-capacity-2 = 
ramp-capacity-3 = 
ramp-capacity-4 = 

animation-charging-0 = 
animation-charging-1 = 
animation-charging-2 = 
animation-charging-framerate = 750

;; _-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_
EOF
)"

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "Se agregaria modulo battery (${bat_name}${adapter_name:+ / $adapter_name}) en: $target"
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

  log "Agregado modulo battery en: $target"
}

_ensure_polybar_shapes_nobat_glyph() {
  local target="$POLYBAR_SHAPES_MODULES_FILE"
  local block
  block="$(cat <<'EOF'
[module/right3_nobat]
type = custom/text
content-background = ${color.shade5}
content-foreground = ${color.shade3}
content = ${glyph.gright}
content-font = 3

;; _-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_
EOF
)"

  if [[ -f "$target" ]] && grep -Eq '^[[:space:]]*\[module/right3_nobat\]' "$target"; then
    return 0
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "Se agregaria modulo right3_nobat en: $target"
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

  log "Agregado modulo right3_nobat en: $target"
}

_patch_shapes_modules_right_pattern() {
  local target="$1"
  local sed_expr="$2"
  local dry_msg="$3"
  local log_msg="$4"

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "$dry_msg"
    return 0
  fi

  backup_file_once "$target"
  sed -E -i "$sed_expr" "$target"
  log "$log_msg"
}

_remove_battery_from_polybar_config() {
  local target="$1"
  if [[ ! -f "$target" ]]; then
    return 0
  fi

  local tmp
  tmp="$(mktemp)"

  awk '
    /^[[:space:]]*modules-(left|center|right)[[:space:]]*=/ {
      eq_pos = index($0, "=")
      lhs = substr($0, 1, eq_pos)
      rhs = substr($0, eq_pos + 1)

      n = split(rhs, raw, /[[:space:]]+/)
      m = 0
      has_battery = 0
      for (i = 1; i <= n; i++) {
        if (raw[i] != "") {
          tokens[++m] = raw[i]
          if (raw[i] == "battery") {
            has_battery = 1
          }
        }
      }

      if (!has_battery) {
        print $0
        next
      }

      out_count = 0
      for (i = 1; i <= m; i++) {
        tok = tokens[i]
        if (tok == "battery") {
          if (i == 1 && m >= 2 && tokens[2] == "sep") {
            i++
          } else if (i == m && out_count > 0 && out[out_count] == "sep") {
            out_count--
          }
          continue
        }
        if (tok == "sep" && out_count > 0 && out[out_count] == "sep") {
          continue
        }
        out[++out_count] = tok
      }

      line_out = lhs
      for (i = 1; i <= out_count; i++) {
        line_out = line_out " " out[i]
      }
      print line_out
      next
    }

    {
      print $0
    }
  ' "$target" > "$tmp"

  if cmp -s "$target" "$tmp"; then
    rm -f "$tmp"
    return 0
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "Se ocultaria modulo battery en: $target"
    rm -f "$tmp"
    return 0
  fi

  backup_file_once "$target"
  cat "$tmp" > "$target"
  rm -f "$tmp"
  log "Ocultado modulo battery en: $target"
}

ensure_polybar_battery_module() {
  local polybar_dir="${POLYBAR_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/polybar}"

  if [[ ! -d "$polybar_dir" ]]; then
    warn "No existe directorio de Polybar: $polybar_dir; se omite configuracion de bateria."
    return 0
  fi

  local bat_name=""
  local adapter_name=""
  bat_name="$(detect_system_battery || true)"
  adapter_name="$(detect_power_adapter || true)"

  if [[ -n "$bat_name" ]]; then
    log "Bateria del sistema detectada: ${bat_name} (adaptador: ${adapter_name:-ninguno})"

    if [[ -d "${polybar_dir}/shapes" ]]; then
      _ensure_polybar_shapes_battery_definition "$bat_name" "$adapter_name"

      if [[ -f "$POLYBAR_SHAPES_CONFIG_FILE" ]]; then
        if grep -Eq '^modules-right[[:space:]]*=.*\bright3_nobat\b' "$POLYBAR_SHAPES_CONFIG_FILE"; then
          _patch_shapes_modules_right_pattern \
            "$POLYBAR_SHAPES_CONFIG_FILE" \
            '/^modules-right[[:space:]]*=/ s/\bright3_nobat\b/right4 battery right3/g' \
            "Se restauraria modulo battery en modules-right de: $POLYBAR_SHAPES_CONFIG_FILE" \
            "Restaurado modulo battery en modules-right: $POLYBAR_SHAPES_CONFIG_FILE"
        elif ! grep -Eq '^modules-(left|center|right)[[:space:]]*=.*\bbattery\b' "$POLYBAR_SHAPES_CONFIG_FILE"; then
          if grep -Eq '^modules-right[[:space:]]*=.*\bright4[[:space:]]+right3\b' "$POLYBAR_SHAPES_CONFIG_FILE"; then
            _patch_shapes_modules_right_pattern \
              "$POLYBAR_SHAPES_CONFIG_FILE" \
              '/^modules-right[[:space:]]*=/ s/\bright4[[:space:]]+right3\b/right4 battery right3/g' \
              "Se insertaria modulo battery entre right4 y right3 en: $POLYBAR_SHAPES_CONFIG_FILE" \
              "Insertado modulo battery en modules-right: $POLYBAR_SHAPES_CONFIG_FILE"
          elif grep -Eq '^modules-right[[:space:]]*=.*\bright3[[:space:]]+network\b' "$POLYBAR_SHAPES_CONFIG_FILE"; then
            _patch_shapes_modules_right_pattern \
              "$POLYBAR_SHAPES_CONFIG_FILE" \
              '/^modules-right[[:space:]]*=/ s/\bright3[[:space:]]+network\b/right4 battery right3 network/g' \
              "Se insertaria modulo battery en modules-right de: $POLYBAR_SHAPES_CONFIG_FILE" \
              "Insertado modulo battery en modules-right: $POLYBAR_SHAPES_CONFIG_FILE"
          fi
        fi
      fi
    fi

    local ini_file
    while IFS= read -r ini_file; do
      _update_polybar_ini_battery_fields "$ini_file" "$bat_name" "$adapter_name"
    done < <(find "$polybar_dir" -maxdepth 3 -type f \( -name 'modules.ini' -o -name 'bars.ini' \) | LC_ALL=C sort)
  else
    log "No se detecto bateria del sistema en ${POWER_SUPPLY_DIR:-/sys/class/power_supply}; ocultando modulo battery en Polybar."

    if [[ -f "$POLYBAR_SHAPES_CONFIG_FILE" ]]; then
      if grep -Eq '^modules-right[[:space:]]*=.*\bright4[[:space:]]+battery[[:space:]]+right3\b' "$POLYBAR_SHAPES_CONFIG_FILE"; then
        _ensure_polybar_shapes_nobat_glyph
        _patch_shapes_modules_right_pattern \
          "$POLYBAR_SHAPES_CONFIG_FILE" \
          '/^modules-right[[:space:]]*=/ s/\bright4[[:space:]]+battery[[:space:]]+right3\b/right3_nobat/g' \
          "Se ocultaria modulo battery en Polybar shapes usando right3_nobat: $POLYBAR_SHAPES_CONFIG_FILE" \
          "Ocultado modulo battery en Polybar shapes usando right3_nobat: $POLYBAR_SHAPES_CONFIG_FILE"
      elif grep -Eq '^modules-(left|center|right)[[:space:]]*=.*\bbattery\b' "$POLYBAR_SHAPES_CONFIG_FILE"; then
        _remove_battery_from_polybar_config "$POLYBAR_SHAPES_CONFIG_FILE"
      fi
    fi

    local cfg_file
    while IFS= read -r cfg_file; do
      if [[ "$cfg_file" == "$POLYBAR_SHAPES_CONFIG_FILE" ]]; then
        continue
      fi
      _remove_battery_from_polybar_config "$cfg_file"
    done < <(find "$polybar_dir" -maxdepth 3 -type f -name 'config.ini' | LC_ALL=C sort)
  fi
}
