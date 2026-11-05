#!/bin/zsh
# Builds Resources/AppIcon.icns (and docs/icon.png) from design/icon/AppIcon-1024.png with sips and iconutil.
#   tools/make-icon.sh            -> icns from the committed master
#   tools/make-icon.sh --render   -> render the clay icon and notch mark again in Blender first
#                                    (BLENDER=/path/to/Blender, default: the Blender on your PATH)
set -euo pipefail
cd "${0:A:h}/.."
if [[ "${1:-}" == "--render" ]]; then
  blender=${BLENDER:-blender}
  tmp=$(mktemp -d)
  "$blender" -b --factory-startup -P tools/icon/render_icon.py -- icon "$tmp/icon.png" 160 1024
  "$blender" -b --factory-startup -P tools/icon/render_icon.py -- mark "$tmp/mark.png" 96 512
  python3 tools/icon/finish.py "$tmp/icon.png" "$tmp/mark.png"
  rm -rf "$tmp"
fi
set_dir=$(mktemp -d)/AppIcon.iconset
mkdir -p "$set_dir"
for base in 16 32 128 256 512; do
  sips -z $base $base design/icon/AppIcon-1024.png --out "$set_dir/icon_${base}x${base}.png" >/dev/null
  sips -z $((base * 2)) $((base * 2)) design/icon/AppIcon-1024.png --out "$set_dir/icon_${base}x${base}@2x.png" >/dev/null
done
iconutil -c icns "$set_dir" -o Resources/AppIcon.icns
cp design/icon/AppIcon-1024.png docs/icon.png
rm -rf "${set_dir:h}"
echo "wrote Resources/AppIcon.icns and docs/icon.png"
