#!/bin/zsh
# Builds Saku.app with SwiftPM and the Command Line Tools (no Xcode), then signs it ad hoc.
#   ./build.sh            -> build/Saku.app
#   ./build.sh --install  -> also replaces /Applications/Saku.app
set -euo pipefail
cd "${0:A:h}"
swift build -c release
app=build/Saku.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/Saku "$app/Contents/MacOS/Saku"
cp Resources/Info.plist "$app/Contents/"
for f in Resources/*; do
  [[ "$f" == "Resources/Info.plist" ]] || cp -R "$f" "$app/Contents/Resources/"
done
cp docs/FEATURES.md docs/google-tasks-setup.md "$app/Contents/Resources/"
# Ad hoc, but with a designated requirement that survives rebuilds, so macOS keeps the permissions it gave Saku.
codesign --force --sign - --requirements '=designated => identifier "local.saku.app"' "$app"
echo "built $PWD/$app"
if [[ "${1:-}" == "--install" ]]; then
  rm -rf /Applications/Saku.app
  cp -R "$app" /Applications/
  echo "installed /Applications/Saku.app"
fi
