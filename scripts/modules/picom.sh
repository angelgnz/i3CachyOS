#!/usr/bin/env bash

_find_picom_conf() {
  local path
  for path in "$I3_DIR/picom.conf" "$HOME/.config/picom/picom.conf"; do
    if [[ -f "$path" ]]; then
      printf '%s\n' "$path"
      return 0
    fi
  done
  return 1
}

_ensure_picom_list_entries() {
  local candidate="$1"
  local setting_key="$2"
  shift 2
  local entries=("$@")

  local tmp
  tmp="$(mktemp)"

  python3 - "$candidate" "$tmp" "$setting_key" "${entries[@]}" <<'PYEOF'
import re
import sys

src = sys.argv[1]
dst = sys.argv[2]
setting_key = sys.argv[3]
desired_entries = sys.argv[4:]


def split_code_and_comment(line: str):
    in_single = False
    in_double = False
    escaped = False
    for idx, ch in enumerate(line):
        if escaped:
            escaped = False
            continue
        if ch == '\\':
            escaped = True
            continue
        if ch == "'" and not in_double:
            in_single = not in_single
        elif ch == '"' and not in_single:
            in_double = not in_double
        elif ch == '#' and not in_single and not in_double:
            return line[:idx], line[idx:]
    return line, ''


with open(src, 'r', encoding='utf-8') as handle:
    content = handle.read()

pattern = re.compile(
    r'(?m)^([ \t]*' + re.escape(setting_key) + r'\s*=\s*\[)(.*?)(\])',
    re.DOTALL,
)
match = pattern.search(content)

if not match:
    block = f'{setting_key} = [\n' + ',\n'.join(desired_entries) + '\n];\n'
    if content and not content.endswith('\n'):
        content += '\n'
    content += ('\n' if content else '') + block
    with open(dst, 'w', encoding='utf-8') as handle:
        handle.write(content)
    raise SystemExit(0)

header, body, footer = match.groups()
lines = body.splitlines()

while lines and not lines[0].strip():
    lines.pop(0)
while lines and not lines[-1].strip():
    lines.pop()

existing_entries = set()
last_active_idx = None
for idx, line in enumerate(lines):
    code, _ = split_code_and_comment(line)
    normalized = code.strip().rstrip(',')
    if normalized:
        existing_entries.add(normalized)
        last_active_idx = idx

missing_entries = [
    entry for entry in desired_entries
    if entry.strip().rstrip(',') not in existing_entries
]

if not missing_entries:
    with open(dst, 'w', encoding='utf-8') as handle:
        handle.write(content)
    raise SystemExit(0)

if last_active_idx is not None:
    code, comment = split_code_and_comment(lines[last_active_idx])
    code_stripped = code.rstrip()
    trailing_ws = code[len(code_stripped):]
    if not code_stripped.endswith(','):
        lines[last_active_idx] = code_stripped + ',' + trailing_ws + comment

for idx, entry in enumerate(missing_entries):
    suffix = ',' if idx < len(missing_entries) - 1 else ''
    lines.append(entry + suffix)

new_body = '\n' + '\n'.join(lines) + '\n'
new_content = content[:match.start()] + header + new_body + footer + content[match.end():]

with open(dst, 'w', encoding='utf-8') as handle:
    handle.write(new_content)
PYEOF

  local changed=0
  if ! cmp -s "$candidate" "$tmp"; then
    changed=1
  fi

  if [[ $changed -eq 0 ]]; then
    rm -f "$tmp"
    return 1
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    rm -f "$tmp"
    return 0
  fi

  backup_file_once "$candidate"
  cat "$tmp" > "$candidate"
  rm -f "$tmp"
  return 0
}

update_picom_corner_radius() {
  local candidate=""
  if ! candidate="$(_find_picom_conf)"; then
    warn "No se encontro picom.conf. Se omite corner-radius."
    return 0
  fi

  local tmp
  tmp="$(mktemp)"

  awk '
    BEGIN { inblock=0 }
    {
      if ($0 ~ /#-cr-start/) inblock=1
      if (inblock && $0 ~ /^[[:space:]]*corner-radius[[:space:]]*=/) {
        sub(/=.*/, "= 12;")
      }
      print
      if ($0 ~ /#-cr-end/) inblock=0
    }
  ' "$candidate" > "$tmp"

  if ! cmp -s "$candidate" "$tmp"; then
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "Se actualizaria corner-radius a 12 en: $candidate"
    else
      backup_file_once "$candidate"
      cat "$tmp" > "$candidate"
      log "Actualizado corner-radius en: $candidate"
    fi
  else
    log "corner-radius ya estaba configurado en: $candidate"
  fi

  rm -f "$tmp"
}

update_picom_opacity_rule() {
  local candidate=""
  if ! candidate="$(_find_picom_conf)"; then
    warn "No se encontro picom.conf. Se omite opacity-rule."
    return 0
  fi

  if ! command_exists python3; then
    warn "python3 no disponible. Se omite opacity-rule."
    return 0
  fi

  local entries=(
    '  "75:class_g     = '\''Thunar'\''"'
    '  "75:class_g     = '\''Org.xfce.mousepad'\''"'
    '  "90:class_g     = '\''code'\''"'
  )

  if _ensure_picom_list_entries "$candidate" "opacity-rule" "${entries[@]}"; then
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "Se actualizarian las reglas de opacity-rule en: $candidate"
    else
      log "Actualizadas reglas de opacity-rule en: $candidate"
    fi
  else
    log "opacity-rule ya estaba configurado en: $candidate"
  fi
}

update_picom_blur_exclude() {
  local candidate=""
  if ! candidate="$(_find_picom_conf)"; then
    warn "No se encontro picom.conf. Se omite blur-background-exclude."
    return 0
  fi

  if ! command_exists python3; then
    warn "python3 no disponible. Se omite blur-background-exclude."
    return 0
  fi

  local entries=(
    '  "role = '\''xborder'\''"'
    '  "class_g = '\''xborder'\''"'
    '  "name = '\''xborder'\''"'
  )

  if _ensure_picom_list_entries "$candidate" "blur-background-exclude" "${entries[@]}"; then
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "Se agregarian entradas xborder a blur-background-exclude en: $candidate"
    else
      log "Agregadas entradas xborder a blur-background-exclude en: $candidate"
    fi
  else
    log "blur-background-exclude xborder ya estaba presente en: $candidate"
  fi
}

update_picom_refresh_rate_comment() {
  local candidate=""
  if ! candidate="$(_find_picom_conf)"; then
    warn "No se encontro picom.conf. Se omite refresh-rate."
    return 0
  fi

  local tmp
  tmp="$(mktemp)"

  awk '
    /^[[:space:]]*refresh-rate[[:space:]]*=[[:space:]]*0[[:space:]]*;?[[:space:]]*$/ {
      print "#" $0
      next
    }
    { print }
  ' "$candidate" > "$tmp"

  if ! cmp -s "$candidate" "$tmp"; then
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "Se comentaria refresh-rate = 0 en: $candidate"
    else
      backup_file_once "$candidate"
      cat "$tmp" > "$candidate"
      log "Comentado refresh-rate = 0 en: $candidate"
    fi
  else
    log "refresh-rate = 0 ya estaba comentado o ausente en: $candidate"
  fi

  rm -f "$tmp"
}

_ensure_picom_scalar_setting() {
  local candidate="$1"
  local setting_key="$2"
  local setting_value="$3"
  local desired_line="${setting_key} = ${setting_value};"

  local tmp
  tmp="$(mktemp)"

  awk -v key="$setting_key" -v desired="$desired_line" '
    BEGIN { found_active=0; found_commented=0 }
    {
      lines[NR] = $0
      if (!found_active && $0 ~ "^[[:space:]]*" key "[[:space:]]*=") {
        found_active = NR
      } else if (!found_commented && $0 ~ "^[[:space:]]*#[[:space:]]*" key "[[:space:]]*=") {
        found_commented = NR
      }
    }
    END {
      if (found_active > 0) {
        for (i = 1; i <= NR; i++) {
          if (i == found_active) {
            print desired
          } else {
            print lines[i]
          }
        }
      } else if (found_commented > 0) {
        for (i = 1; i <= NR; i++) {
          if (i == found_commented) {
            print desired
          } else {
            print lines[i]
          }
        }
      } else {
        for (i = 1; i <= NR; i++) {
          print lines[i]
        }
        if (NR > 0 && lines[NR] != "") {
          print ""
        }
        print desired
      }
    }
  ' "$candidate" > "$tmp"

  local changed=0
  if ! cmp -s "$candidate" "$tmp"; then
    changed=1
  fi

  if [[ $changed -eq 0 ]]; then
    rm -f "$tmp"
    return 1
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    rm -f "$tmp"
    return 0
  fi

  backup_file_once "$candidate"
  cat "$tmp" > "$candidate"
  rm -f "$tmp"
  return 0
}

update_picom_unredir_if_possible() {
  local candidate=""
  if ! candidate="$(_find_picom_conf)"; then
    warn "No se encontro picom.conf. Se omite unredir-if-possible."
    return 0
  fi

  if _ensure_picom_scalar_setting "$candidate" "unredir-if-possible" "false"; then
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "Se configuraria unredir-if-possible = false; en: $candidate"
    else
      log "Configurado unredir-if-possible = false; en: $candidate"
    fi
  else
    log "unredir-if-possible = false ya estaba configurado en: $candidate"
  fi
}

update_picom_xrender_sync_fence() {
  local candidate=""
  if ! candidate="$(_find_picom_conf)"; then
    warn "No se encontro picom.conf. Se omite xrender-sync-fence."
    return 0
  fi

  if _ensure_picom_scalar_setting "$candidate" "xrender-sync-fence" "true"; then
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "Se configuraria xrender-sync-fence = true; en: $candidate"
    else
      log "Configurado xrender-sync-fence = true; en: $candidate"
    fi
  else
    log "xrender-sync-fence = true ya estaba configurado en: $candidate"
  fi
}

update_picom_rounded_corners_exclude() {
  local candidate=""
  if ! candidate="$(_find_picom_conf)"; then
    warn "No se encontro picom.conf. Se omite rounded-corners-exclude."
    return 0
  fi

  if ! command_exists python3; then
    warn "python3 no disponible. Se omite rounded-corners-exclude."
    return 0
  fi

  local entries=(
    '  "_NET_WM_STATE@:32a *= '\''_NET_WM_STATE_FULLSCREEN'\''"'
  )

  if _ensure_picom_list_entries "$candidate" "rounded-corners-exclude" "${entries[@]}"; then
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "Se agregaria exclusion fullscreen a rounded-corners-exclude en: $candidate"
    else
      log "Agregada exclusion fullscreen a rounded-corners-exclude en: $candidate"
    fi
  else
    log "rounded-corners-exclude fullscreen ya estaba presente en: $candidate"
  fi
}
