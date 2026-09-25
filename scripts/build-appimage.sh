#!/usr/bin/env bash
# Package a built Flutter Linux bundle as an AppImage using appimagetool.
#
# Usage: scripts/build-appimage.sh <bundle-dir> <version> <appimage-arch> <output-file>
set -euo pipefail

BUNDLE_DIR="${1:?usage: build-appimage.sh <bundle-dir> <version> <appimage-arch> <output-file>}"
VERSION="${2:?}"
ARCH="${3:?}"   # x86_64 or aarch64
OUT="${4:?}"

if [ ! -d "$BUNDLE_DIR" ]; then
  echo "build-appimage: bundle dir not found: $BUNDLE_DIR" >&2
  exit 1
fi
if [ "$ARCH" != "x86_64" ] && [ "$ARCH" != "aarch64" ]; then
  echo "build-appimage: unsupported arch: $ARCH" >&2
  exit 1
fi

APPDIR="$(mktemp -d)/bin.AppDir"
trap 'rm -rf "$(dirname "$APPDIR")"' EXIT
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/share/icons/hicolor/256x256/apps" \
  "$APPDIR/usr/share/applications"

cp -a "$BUNDLE_DIR/." "$APPDIR/usr/bin/"
cp "$(dirname "$0")/../assets/icon-1024.png" \
  "$APPDIR/usr/share/icons/hicolor/256x256/apps/bin.png"
cp "$APPDIR/usr/share/icons/hicolor/256x256/apps/bin.png" "$APPDIR/bin.png"

cat > "$APPDIR/usr/share/applications/bin.desktop" <<'DESK'
[Desktop Entry]
Type=Application
Name=bin
Exec=bin
Icon=bin
Categories=Utility;
DESK
cp "$APPDIR/usr/share/applications/bin.desktop" "$APPDIR/bin.desktop"

cat > "$APPDIR/AppRun" <<'RUN'
#!/bin/sh
exec "$(dirname "$0")/usr/bin/bin" "$@"
RUN
chmod +x "$APPDIR/AppRun"

TOOL="$(mktemp -d)/appimagetool"
curl -fsSL --retry 3 -o "$TOOL" \
  "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-${ARCH}.AppImage"
chmod +x "$TOOL"

ARCH="$ARCH" "$TOOL" "$APPDIR" "$OUT"
echo "build-appimage: $OUT"
