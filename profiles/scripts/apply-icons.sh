#!/usr/bin/env bash
# Matugen icon theme: Papirus-Matugen — a lightweight overlay theme that
# inherits Papirus-(Dark|Light) and recolors only the folder icons to the
# current matugen primary. Call with the theme mode (dark/light).
set -euo pipefail

mode="${1:-dark}"
scheme="$HOME/.cache/matugen/scheme.json"
[ -f "$scheme" ] || { echo "no scheme yet"; exit 0; }

primary=$(jq -r '.colors.primary.default.color' "$scheme" | tr -d '#')
darker=$(python3 -c "
h = '$primary'
print(''.join(f'{int(c * 0.78):02x}' for c in (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))))")

# Theme name includes the primary so GTK sees a *change* and reloads icons in
# running apps (a stable name would keep the old cached SVG on color switches).
if [ "$mode" = light ]; then
  base=Papirus-Light; theme="Papirus-Matugen-L-$primary"
else
  base=Papirus-Dark; theme="Papirus-Matugen-$primary"
fi

src="/usr/share/icons/$base"
dst="$HOME/.local/share/icons/$theme"
mapfile -t sizes < <(ls "$src" | grep -E '^[0-9]')

# skip the rebuild if mode+primary are unchanged and the theme exists (speeds
# up re-applies like login or a toggle that doesn't change the palette)
state_file="$HOME/.cache/matugen/icon-theme-state"
if [ -d "$dst" ] && [ -f "$state_file" ]; then
  read -r last_mode last_primary < "$state_file"
  if [ "$last_mode" = "$mode" ] && [ "$last_primary" = "$primary" ]; then
    gsettings set org.gnome.desktop.interface icon-theme "$theme"
    echo "icon theme unchanged ($theme) — skip rebuild"
    exit 0
  fi
fi

# drop stale matugen icon themes from previous primaries
for old in "$HOME"/.local/share/icons/Papirus-Matugen*; do
  [ -d "$old" ] && [ "$old" != "$dst" ] && rm -rf "$old"
done

rm -rf "$dst"
mkdir -p "$dst"

dirs=$(printf '%s/places,' "${sizes[@]}" | sed 's/,$//')
cat > "$dst/index.theme" <<EOF
[Icon Theme]
Name=$theme
Comment=Matugen-tinted Papirus folder icons
Inherits=$base
Directories=$dirs
EOF
for size in "${sizes[@]}"; do
  scale=1
  [[ "$size" == *@2x ]] && scale=2
  echo ""
  echo "[$size/places]"
  echo "Size=${size%%x*}"
  echo "Scale=$scale"
done >> "$dst/index.theme"

for size in "${sizes[@]}"; do
  mkdir -p "$dst/$size/places"
  for blue in "$src/$size/places/folder-blue"{-*,}.svg "$src/$size/places/user-blue"{-*,}.svg; do
    [ -f "$blue" ] || continue
    name="${blue##*/}"
    matugen="${name/-blue/-matugen}"
    sed -e "s/#5294e2/#$primary/gi" -e "s/#4877b1/#$darker/gi" "$blue" > "$dst/$size/places/$matugen"
    ln -sf "$matugen" "$dst/$size/places/${name/-blue/}"
  done
done

gsettings set org.gnome.desktop.interface icon-theme "$theme"
gtk-update-icon-cache -f "$dst" >/dev/null 2>&1 || true
echo "$mode $primary" > "$state_file"
echo "icon theme -> $theme (folder #$primary, ${#sizes[@]} sizes)"
