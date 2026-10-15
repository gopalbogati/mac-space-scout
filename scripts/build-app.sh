#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$ROOT"
export MACOSX_DEPLOYMENT_TARGET=13.0
VERSION=0.1.0
DIST="$ROOT/dist"
APP="$DIST/SpaceScout.app"
mkdir -p "$DIST" "$ROOT/.build/SpaceScout.iconset"
for ARCH in arm64 x86_64; do
  swift build -c release --product SpaceScout --arch "$ARCH" --scratch-path "$ROOT/.build/package-$ARCH" \
    -Xswiftc -gnone -Xswiftc -debug-prefix-map -Xswiftc "$ROOT=/SpaceScout" \
    -Xcc "-fdebug-prefix-map=$ROOT=/SpaceScout"
done
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
ARM_BIN="$(swift build -c release --arch arm64 --scratch-path "$ROOT/.build/package-arm64" --show-bin-path)"
INTEL_BIN="$(swift build -c release --arch x86_64 --scratch-path "$ROOT/.build/package-x86_64" --show-bin-path)"
lipo -create "$ARM_BIN/SpaceScout" "$INTEL_BIN/SpaceScout" -output "$APP/Contents/MacOS/SpaceScout"
strip -S -x "$APP/Contents/MacOS/SpaceScout"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
swift "$ROOT/scripts/make-icon.swift" "$ROOT/.build/SpaceScout.iconset"
iconutil -c icns "$ROOT/.build/SpaceScout.iconset" -o "$APP/Contents/Resources/SpaceScout.icns"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE.txt"
if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$APP"
else
  codesign --force --sign - "$APP"
  echo "Ad-hoc signed preview. Not Developer ID signed; not notarized."
fi
codesign --verify --deep --strict "$APP"
ARCHIVE="SpaceScout-$VERSION-universal.zip"
rm -f "$DIST/$ARCHIVE"
ditto -c -k --keepParent "$APP" "$DIST/$ARCHIVE"
(cd "$DIST" && shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256")
lipo -info "$APP/Contents/MacOS/SpaceScout"
echo "Built $APP"
echo "Archive: $DIST/$ARCHIVE"
