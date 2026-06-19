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
    "role = 'xborder'"
    "class_g = 'xborder'"
    "name = 'xborder'"
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

  awk -v entries="role = 'xborder'|class_g = 'xborder'|name = 'xborder'" '
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
    "  role = 'xborder'",
    "  class_g = 'xborder'",
    "  name = 'xborder'",
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
