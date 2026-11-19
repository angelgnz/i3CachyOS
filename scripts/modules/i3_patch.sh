#!/usr/bin/env bash

ensure_steam_settings_floating_rule() {
  local target_file="${1:-$I3_CONFIG}"
  local steam_rules=(
    'for_window [title="Steam Settings"] floating enable'
    'for_window [title="Configuraciones de.*Steam"] floating enable'
  )
  local rule
  local added=0

  for rule in "${steam_rules[@]}"; do
    if grep -Fxq "$rule" "$target_file"; then
      continue
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
      if grep -Eq 'floating[[:space:]]+enable' "$target_file"; then
        dry "Se agregaria regla de Steam Settings despues del ultimo floating enable en: $I3_CONFIG"
      else
        dry "No se encontro floating enable en: $I3_CONFIG; se agregaria regla de Steam Settings al final"
      fi
    fi

    if [[ "$target_file" == "$I3_CONFIG" ]]; then
      if [[ $DRY_RUN -eq 1 ]]; then
        continue
      fi
      backup_file_once "$I3_CONFIG"
    fi

    local tmp
    tmp="$(mktemp)"

    awk -v steam_rule="$rule" '
    {
      lines[NR] = $0
      if ($0 ~ /floating[[:space:]]+enable/) {
        last_floating = NR
      }
    }
    END {
      if (NR == 0) {
        print steam_rule
        exit
      }

      for (i = 1; i <= NR; i++) {
        print lines[i]
        if (i == last_floating) {
          print steam_rule
        }
      }

      if (last_floating == 0) {
        print steam_rule
      }
    }
    ' "$target_file" > "$tmp"

    cat "$tmp" > "$target_file"
    rm -f "$tmp"
    added=1
  done

  if [[ $added -eq 1 && $DRY_RUN -ne 1 ]]; then
    log "Regla Steam Settings agregada en: $I3_CONFIG"
  fi
}

_patch_i3_exec_bind() {
  local target_file="$1"
  local key_combo="$2"
  local key_regex="$3"
  local exec_target="$4"
  local label="$5"
  local desired_line="bindsym ${key_combo} exec \"${exec_target}\""

  if grep -Fxq "$desired_line" "$target_file"; then
    return 0
  fi

  if grep -Eq "^bindsym ${key_regex}[[:space:]]+exec .*" "$target_file"; then
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "Se actualizaria ${label} en ${key_combo} dentro de $I3_CONFIG"
    fi
    sed -E -i "s|^bindsym ${key_regex}[[:space:]]+exec .*$|${desired_line}|" "$target_file"
  else
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "Se agregaria ${label} en ${key_combo} dentro de $I3_CONFIG"
    fi
    printf '\n%s\n' "$desired_line" >> "$target_file"
  fi
}

command_i3_patch() {
  ensure_i3_config_exists

  if [[ $DRY_RUN -ne 1 && ! -f "$I3_CONFIG" ]]; then
    err "No existe i3 config en: $I3_CONFIG"
    return 1
  fi

  local work_file
  work_file="$(mktemp)"

  if [[ -f "$I3_CONFIG" ]]; then
    render_without_managed_block "$I3_CONFIG" > "$work_file"
  else
    default_i3_config_content > "$work_file"
  fi

  if grep -Eq '^bindsym \$mod\+a[[:space:]]+focus parent' "$work_file"; then
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "Se comentaria bindsym \$mod+a focus parent en $I3_CONFIG"
    fi
    sed -E -i 's/^bindsym \$mod\+a[[:space:]]+focus parent/#bindsym $mod+a focus parent/' "$work_file"
  fi

  _patch_i3_exec_bind "$work_file" '$mod+a' '\$mod\+a' '~/.config/i3/scripts/i3_rofi_apps' 'launcher rofi'
  _patch_i3_exec_bind "$work_file" '$mod+Shift+e' '\$mod\+Shift\+e' '~/.config/i3/scripts/i3_rofi_powermenu' 'powermenu'
  _patch_i3_exec_bind "$work_file" '$mod+x' '\$mod\+x' '~/.config/i3/scripts/i3_rofi_powermenu' 'powermenu'
  _patch_i3_exec_bind "$work_file" '$mod+Shift+t' '\$mod\+Shift\+t' '~/.config/i3/scripts/i3_rofi_polybar_theme' 'selector de tema polybar'

  if grep -Eq '^for_window \[class="\^\.\*"\] border pixel [1-9][0-9]*' "$work_file"; then
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "Se ajustaria border pixel a 0 para class=^.* en $I3_CONFIG"
    fi
    sed -E -i 's/^for_window \[class="\^\.\*"\] border pixel [0-9]+/for_window [class="^.*"] border pixel 0/' "$work_file"
  fi

  if grep -Eq '^[[:space:]]*(#exec xrandr --output HDMI-1 --mode 1920x1080 --rate 60 --scale 1x1|#exec xrandr --auto --output HDMI-1 --mode 1920x1080 --above HDMI-2|#exec feh --bg-fill ~/\.config/i3/wallpaper\.png|exec_always[[:space:]]+--no-startup-id[[:space:]]+~/\.config/polybar/launch\.sh([[:space:]]+--shapes)?)[[:space:]]*$' "$work_file"; then
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "Se limpiarian lineas legacy de xrandr/feh y launch.sh antiguo en: $I3_CONFIG"
    fi
  fi

  sed -E -i '/^[[:space:]]*#exec xrandr --output HDMI-1 --mode 1920x1080 --rate 60 --scale 1x1[[:space:]]*$/d' "$work_file"
  sed -E -i '/^[[:space:]]*#exec xrandr --auto --output HDMI-1 --mode 1920x1080 --above HDMI-2[[:space:]]*$/d' "$work_file"
  sed -E -i '/^[[:space:]]*#exec feh --bg-fill ~\/\.config\/i3\/wallpaper\.png[[:space:]]*$/d' "$work_file"
  sed -E -i '/^[[:space:]]*exec_always[[:space:]]+--no-startup-id[[:space:]]+~\/\.config\/polybar\/launch\.sh([[:space:]]+--shapes)?[[:space:]]*$/d' "$work_file"
  sed -E -i '/^[[:space:]]*exec_always[[:space:]]+--no-startup-id[[:space:]]+.*i3_polybar_set_theme[[:space:]]+--current[[:space:]]*$/d' "$work_file"

  ensure_steam_settings_floating_rule "$work_file"

  local autostart_helpers_block=""
  if [[ ! -f "$I3_AUTOSTART" ]]; then
    autostart_helpers_block="exec --no-startup-id ${I3_SCRIPTS_DIR}/i3_nzxt
exec --no-startup-id ${I3_SCRIPTS_DIR}/i3_cloud_storage
"
  fi

  if grep -Eq '^[[:space:]]*bindsym[[:space:]]+\$mod\+p[[:space:]]+' "$work_file"; then
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "Se comentaria bindsym \$mod+p en $I3_CONFIG"
    fi
    sed -E -i 's/^[[:space:]]*bindsym[[:space:]]+\$mod\+p[[:space:]]+/#bindsym $mod+p /' "$work_file"
  fi

  if grep -Eq '^[[:space:]]*bindsym[[:space:]]+\$mod\+Shift\+p[[:space:]]+' "$work_file"; then
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "Se comentaria bindsym \$mod+Shift+p en $I3_CONFIG"
    fi
    sed -E -i 's/^[[:space:]]*bindsym[[:space:]]+\$mod\+Shift\+p[[:space:]]+/#bindsym $mod+Shift+p /' "$work_file"
  fi

  local managed_block
  managed_block="$(cat <<EOF
# Scripts auxiliares
exec --no-startup-id kwalletd6
${autostart_helpers_block}exec --no-startup-id gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

# Configuracion de monitores (dinamica + hot-plug)
exec --no-startup-id ${SCREENLAYOUT_FILE}
exec_always --no-startup-id ${SCREENLAYOUT_FILE} --watch

# Status Bar:
exec_always --no-startup-id ${I3_SCRIPTS_DIR}/i3_polybar_set_theme --current

# Borders
gaps inner ${I3_GAP_SIZE}
exec xborders --border-width 2 --border-radius 12

# Configuracion de i3-layouts
exec i3-layouts

set \$i3l spiral to workspace 1
set \$i3l spiral to workspace 2
set \$i3l spiral to workspace 3
set \$i3l spiral to workspace 4
set \$i3l spiral to workspace 5
set \$i3l spiral to workspace 6
set \$i3l spiral to workspace 7
set \$i3l spiral to workspace 8
set \$i3l spiral to workspace 9
set \$i3l spiral to workspace 0

# Configuracion de wallpaper
exec_always --no-startup-id ${I3_SCRIPTS_DIR}/i3_wallpaper

# Configuracion de Flameshot
exec --no-startup-id flameshot
bindsym \$mod+p exec flameshot full -c
bindsym \$mod+Shift+p exec flameshot gui
EOF
)"

  append_managed_block "$work_file" "$managed_block" "no-backup"

  if [[ -f "$I3_CONFIG" ]] && cmp -s "$I3_CONFIG" "$work_file"; then
    rm -f "$work_file"
    log "i3 config ya estaba actualizado: $I3_CONFIG"
  elif [[ $DRY_RUN -eq 1 ]]; then
    dry "Se actualizaria configuracion de i3 en: $I3_CONFIG"
    rm -f "$work_file"
  else
    backup_file_once "$I3_CONFIG"
    cat "$work_file" > "$I3_CONFIG"
    rm -f "$work_file"
    log "Actualizado i3 config: $I3_CONFIG"
  fi

  verify_screenlayout_config_applied
}
