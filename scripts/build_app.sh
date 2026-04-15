#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Jibegaza MenuBar"
EXECUTABLE_NAME="TimeCalculatorMenuBar"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
RELEASE_BINARY="$ROOT_DIR/.build/release/$EXECUTABLE_NAME"
ZIP_PATH="$ROOT_DIR/dist/$APP_NAME.zip"
ICON_PATH="$ROOT_DIR/Resources/AppIcon.icns"

mkdir -p "$ROOT_DIR/dist"

echo "Building release binary..."
swift build -c release --package-path "$ROOT_DIR"

if [[ ! -f "$RELEASE_BINARY" ]]; then
  echo "Release binary not found: $RELEASE_BINARY" >&2
  exit 1
fi

echo "Assembling app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$RELEASE_BINARY" "$MACOS_DIR/$EXECUTABLE_NAME"
chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"

if [[ -f "$ICON_PATH" ]]; then
  cp "$ICON_PATH" "$RESOURCES_DIR/AppIcon.icns"
fi

if command -v codesign >/dev/null 2>&1; then
  echo "Applying ad-hoc code signature..."
  codesign --force --deep --sign - "$APP_DIR"
fi

echo "Creating zip for sharing..."
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

echo
echo "Done."
echo "App: $APP_DIR"
echo "Zip: $ZIP_PATH"
echo
echo "Run it with:"
echo "open \"$APP_DIR\""
