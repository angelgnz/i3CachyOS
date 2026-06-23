#!/usr/bin/env bash

ensure_steam_settings_floating_rule() {
  local steam_rules=(
    'for_window [title="Steam Settings"] floating enable'
    'for_window [title="Configuraciones de.*Steam"] floating enable'
  )
  local rule

  for rule in "${steam_rules[@]}"; do
    if grep -Fxq "$rule" "$I3_CONFIG"; then
      continue
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
      if grep -Eq 'floating[[:space:]]+enable' "$I3_CONFIG"; then
        dry "Se agregaria regla de Steam Settings despues del ultimo floating enable en: $I3_CONFIG"
      else
        dry "No se encontro floating enable en: $I3_CONFIG; se agregaria regla de Steam Settings al final"
      fi
      continue
    fi

    backup_file_once "$I3_CONFIG"

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
    ' "$I3_CONFIG" > "$tmp"

    cat "$tmp" > "$I3_CONFIG"
    rm -f "$tmp"
  done

  log "Regla Steam Settings agregada en: $I3_CONFIG"
}

command_i3_patch() {
  ensure_i3_config_exists

  if [[ ! -f "$I3_CONFIG" ]]; then
    err "No existe i3 config en: $I3_CONFIG"
    return 1
  fi

  if [[ $DRY_RUN -ne 1 ]]; then
    backup_file_once "$I3_CONFIG"
  fi

  if grep -Eq '^bindsym \$mod\+a[[:space:]]+focus parent' "$I3_CONFIG"; then
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "Se comentaria bindsym \$mod+a focus parent en $I3_CONFIG"
    else
      sed -E -i 's/^bindsym \$mod\+a[[:space:]]+focus parent/#bindsym $mod+a focus parent/' "$I3_CONFIG"
    fi
  fi

  if grep -Eq '^bindsym \$mod\+a[[:space:]]+exec .*' "$I3_CONFIG"; then
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "Se actualizaria launcher rofi en \$mod+a dentro de $I3_CONFIG"
    else
      sed -E -i 's|^bindsym \$mod\+a[[:space:]]+exec .*$|bindsym $mod+a exec "~/.config/i3/scripts/i3_rofi_apps"|' "$I3_CONFIG"
    fi
  else
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "Se agregaria launcher rofi en \$mod+a dentro de $I3_CONFIG"
    else
      printf '\n%s\n' 'bindsym $mod+a exec "~/.config/i3/scripts/i3_rofi_apps"' >> "$I3_CONFIG"
    fi
  fi

  if grep -Eq '^bindsym \$mod\+Shift\+e[[:space:]]+exec .*' "$I3_CONFIG"; then
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "Se actualizaria powermenu en \$mod+Shift+e dentro de $I3_CONFIG"
    else
      sed -E -i 's|^bindsym \$mod\+Shift\+e[[:space:]]+exec .*$|bindsym $mod+Shift+e exec "~/.config/i3/scripts/i3_rofi_powermenu"|' "$I3_CONFIG"
    fi
  else
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "Se agregaria powermenu en \$mod+Shift+e dentro de $I3_CONFIG"
    else
      printf '\n%s\n' 'bindsym $mod+Shift+e exec "~/.config/i3/scripts/i3_rofi_powermenu"' >> "$I3_CONFIG"
    fi
  fi

  if grep -Eq '^bindsym \$mod\+x[[:space:]]+exec .*' "$I3_CONFIG"; then
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "Se actualizaria powermenu en \$mod+x dentro de $I3_CONFIG"
    else
      sed -E -i 's|^bindsym \$mod\+x[[:space:]]+exec .*$|bindsym $mod+x exec "~/.config/i3/scripts/i3_rofi_powermenu"|' "$I3_CONFIG"
    fi
  else
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "Se agregaria powermenu en \$mod+x dentro de $I3_CONFIG"
    else
      printf '\n%s\n' 'bindsym $mod+x exec "~/.config/i3/scripts/i3_rofi_powermenu"' >> "$I3_CONFIG"
    fi
  fi

  if grep -Eq '^bindsym \$mod\+Shift\+t[[:space:]]+exec .*' "$I3_CONFIG"; then
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "Se actualizaria selector de tema polybar en \$mod+Shift+t dentro de $I3_CONFIG"
    else
      sed -E -i 's|^bindsym \$mod\+Shift\+t[[:space:]]+exec .*$|bindsym $mod+Shift+t exec "~/.config/i3/scripts/i3_rofi_polybar_theme"|' "$I3_CONFIG"
    fi
  else
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "Se agregaria selector de tema polybar en \$mod+Shift+t dentro de $I3_CONFIG"
    else
      printf '\n%s\n' 'bindsym $mod+Shift+t exec "~/.config/i3/scripts/i3_rofi_polybar_theme"' >> "$I3_CONFIG"
    fi
  fi

  if grep -Eq '^for_window \[class="\^\.\*"\] border pixel [0-9]+' "$I3_CONFIG"; then
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "Se ajustaria border pixel a 0 para class=^.* en $I3_CONFIG"
    else
      sed -E -i 's/^for_window \[class="\^\.\*"\] border pixel [0-9]+/for_window [class="^.*"] border pixel 0/' "$I3_CONFIG"
    fi
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "Se limpiarian lineas legacy de xrandr/feh y launch.sh antiguo en: $I3_CONFIG"
  else
    backup_file_once "$I3_CONFIG"
    sed -E -i '/^[[:space:]]*#exec xrandr --output HDMI-1 --mode 1920x1080 --rate 60 --scale 1x1[[:space:]]*$/d' "$I3_CONFIG"
    sed -E -i '/^[[:space:]]*#exec xrandr --auto --output HDMI-1 --mode 1920x1080 --above HDMI-2[[:space:]]*$/d' "$I3_CONFIG"
    sed -E -i '/^[[:space:]]*#exec feh --bg-fill ~\/\.config\/i3\/wallpaper\.png[[:space:]]*$/d' "$I3_CONFIG"
    sed -E -i '/^[[:space:]]*exec_always[[:space:]]+--no-startup-id[[:space:]]+~\/\.config\/polybar\/launch\.sh([[:space:]]+--shapes)?[[:space:]]*$/d' "$I3_CONFIG"
  fi

  ensure_steam_settings_floating_rule

  local managed_block
  managed_block="$(cat <<EOF
# Scripts auxiliares
exec --no-startup-id kwalletd6
exec --no-startup-id ${I3_SCRIPTS_DIR}/i3_nzxt
exec --no-startup-id ${I3_SCRIPTS_DIR}/i3_cloud_storage
exec --no-startup-id gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

# Configuracion de monitor doble
exec --no-startup-id ${SCREENLAYOUT_FILE}

# Status Bar:
exec_always --no-startup-id ~/.config/polybar/launch.sh --shapes

# Borders
gaps inner 12
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
exec --no-startup-id setwallpaper "/home/angel/Images/wallpapers/edger_lucy_neon-16-9.jpg" --mode span
EOF
)"

  append_managed_block "$I3_CONFIG" "$managed_block"
  verify_screenlayout_config_applied
}
