#!/usr/bin/env bash

update_picom_corner_radius() {
  local candidate=""
  local path
  for path in "$I3_DIR/picom.conf" "$HOME/.config/picom/picom.conf"; do
    if [[ -f "$path" ]]; then
      candidate="$path"
      break
    fi
  done

  if [[ -z "$candidate" ]]; then
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
  local path
  for path in "$I3_DIR/picom.conf" "$HOME/.config/picom/picom.conf"; do
    if [[ -f "$path" ]]; then
      candidate="$path"
      break
    fi
  done

  if [[ -z "$candidate" ]]; then
    warn "No se encontro picom.conf. Se omite opacity-rule."
    return 0
  fi

  local tmp
  tmp="$(mktemp)"

  python3 - "$candidate" "$tmp" <<'PYEOF'
import re
import sys

src = sys.argv[1]
dst = sys.argv[2]

desired_entries = [
  '  "75:class_g     = '\''Thunar'\''",',
  '  "75:class_g     = '\''Org.xfce.mousepad'\''"',
]

with open(src, 'r', encoding='utf-8') as handle:
    content = handle.read()

pattern = re.compile(r'(opacity-rule\s*=\s*\[)(.*?)(\])', re.DOTALL)
match = pattern.search(content)

if not match:
    block = 'opacity-rule = [\n' + '\n'.join(desired_entries) + '\n];\n'
    if content and not content.endswith('\n'):
        content += '\n'
    content += '\n' + block
    with open(dst, 'w', encoding='utf-8') as handle:
        handle.write(content)
    raise SystemExit(0)

header, body, footer = match.groups()
body_lines = body.splitlines()
existing_entries = set(line.strip().rstrip(',') for line in body_lines)
missing_entries = [entry for entry in desired_entries if entry.strip().rstrip(',') not in existing_entries]

if not missing_entries:
    with open(dst, 'w', encoding='utf-8') as handle:
        handle.write(content)
    raise SystemExit(0)

body = body.rstrip()
if body and not body.endswith(','):
    body += ','

for index, entry in enumerate(missing_entries):
    body += '\n' + entry
    if index < len(missing_entries) - 1:
        body += ','

body += '\n'
new_content = content[:match.start()] + header + body + footer + content[match.end():]

with open(dst, 'w', encoding='utf-8') as handle:
    handle.write(new_content)
PYEOF

  if ! cmp -s "$candidate" "$tmp"; then
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "Se actualizarian las reglas de opacity-rule en: $candidate"
    else
      backup_file_once "$candidate"
      cat "$tmp" > "$candidate"
      log "Actualizadas reglas de opacity-rule en: $candidate"
    fi
  else
    log "opacity-rule ya estaba configurado en: $candidate"
  fi

  rm -f "$tmp"
}

update_picom_blur_exclude() {
  local candidate=""
  local path
  for path in "$I3_DIR/picom.conf" "$HOME/.config/picom/picom.conf"; do
    if [[ -f "$path" ]]; then
      candidate="$path"
      break
    fi
  done

  if [[ -z "$candidate" ]]; then
    warn "No se encontro picom.conf. Se omite blur-background-exclude."
    return 0
  fi

  local entries=(
    '  "role = '\''xborder'\''",'
    '  "class_g = '\''xborder'\''",'
    '  "name = '\''xborder'\''",'
  )

  local all_present=1
  local entry
  for entry in "${entries[@]}"; do
    if ! grep -Fq "$entry" "$candidate"; then
      all_present=0
      break
    fi
  done

  if [[ $all_present -eq 1 ]]; then
    log "blur-background-exclude xborder ya configurado en: $candidate"
    return 0
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "Se agregarian entradas xborder a blur-background-exclude en: $candidate"
    return 0
  fi

  local tmp
  tmp="$(mktemp)"

  awk -v entries='"  \"role = '\''xborder'\''\","|  \"class_g = '\''xborder'\''\","|  \"name = '\''xborder'\''\","' '
    BEGIN {
      inblock = 0
      done = 0
      n = split(entries, arr, "|")
    }
    !done && /blur-background-exclude[[:space:]]*=/ { inblock = 1 }
    inblock && /\]/ && !done {
      for (i = 1; i <= n; i++) {
        found = 0
        while ((getline line < FILENAME) > 0) { close(FILENAME); break }
        found = 0
      }
      for (i = 1; i <= n; i++) {
        if (!seen[arr[i]]) {
          print "  " arr[i] ","
        }
      }
      done = 1
    }
    { seen[$0] = 1; print }
  ' "$candidate" > /dev/null

  python3 - "$candidate" "$tmp" <<'PYEOF'
import sys, re

src = sys.argv[1]
dst = sys.argv[2]

new_entries = [
  '  "role = '\''xborder'\''",',
  '  "class_g = '\''xborder'\''",',
  '  "name = '\''xborder'\''",',
]

with open(src, 'r') as f:
    content = f.read()

pattern = re.compile(
    r'(blur-background-exclude\s*=\s*\[)(.*?)(\])',
    re.DOTALL
)

def insert_missing(m):
    header = m.group(1)
    body   = m.group(2)
    footer = m.group(3)
    for ne in new_entries:
        key = ne.strip().rstrip(',')
        if key not in body:
            body = body.rstrip()
            if body and not body.endswith(','):
                body += ','
            body += '\n' + ne + ',\n'
    return header + body + footer

new_content = pattern.sub(insert_missing, content, count=1)

with open(dst, 'w') as f:
    f.write(new_content)
PYEOF

  if ! cmp -s "$candidate" "$tmp"; then
    backup_file_once "$candidate"
    cat "$tmp" > "$candidate"
    log "Agregadas entradas xborder a blur-background-exclude en: $candidate"
  else
    log "blur-background-exclude xborder ya estaba presente en: $candidate"
  fi

  rm -f "$tmp"
}

update_picom_refresh_rate_comment() {
  local candidate=""
  local path
  for path in "$I3_DIR/picom.conf" "$HOME/.config/picom/picom.conf"; do
    if [[ -f "$path" ]]; then
      candidate="$path"
      break
    fi
  done

  if [[ -z "$candidate" ]]; then
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
