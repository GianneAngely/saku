#!/bin/zsh
# Makes the GitHub release zip: a universal Saku.app (Apple silicon + Intel), signed ad hoc, and its SHA-256.
#   tools/release.sh   -> dist/Saku-<version>.zip
set -euo pipefail
cd "${0:A:h:h}"
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
./build.sh
swift build -c release --triple x86_64-apple-macosx26.0
lipo -create .build/arm64-apple-macosx/release/Saku .build/x86_64-apple-macosx/release/Saku -output build/Saku.app/Contents/MacOS/Saku
codesign --force --sign - --requirements '=designated => identifier "local.saku.app"' build/Saku.app
mkdir -p dist
rm -f "dist/Saku-$version.zip"
ditto -c -k --sequesterRsrc --keepParent build/Saku.app "dist/Saku-$version.zip"
lipo -archs build/Saku.app/Contents/MacOS/Saku
shasum -a 256 "dist/Saku-$version.zip"
