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
EXPORT_IMAGE_PATH="$ROOT_DIR/Assets/Export/앱_실행_방법.png"
DIST_EXPORT_IMAGE_PATH="$ROOT_DIR/dist/앱_실행_방법.png"
PACKAGE_DIR="$ROOT_DIR/dist/$APP_NAME Package"

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

if [[ -f "$EXPORT_IMAGE_PATH" ]]; then
  echo "Copying export image..."
  cp "$EXPORT_IMAGE_PATH" "$DIST_EXPORT_IMAGE_PATH"
fi

if command -v codesign >/dev/null 2>&1; then
  echo "Applying ad-hoc code signature..."
  codesign --force --deep --sign - "$APP_DIR"
fi

echo "Creating zip for sharing..."
rm -f "$ZIP_PATH"
rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR"
cp -R "$APP_DIR" "$PACKAGE_DIR/"

if [[ -f "$DIST_EXPORT_IMAGE_PATH" ]]; then
  cp "$DIST_EXPORT_IMAGE_PATH" "$PACKAGE_DIR/"
fi

ditto -c -k --sequesterRsrc --keepParent "$PACKAGE_DIR" "$ZIP_PATH"
rm -rf "$PACKAGE_DIR"

echo
echo "Done."
echo "App: $APP_DIR"
echo "Zip: $ZIP_PATH"
echo
echo "Run it with:"
echo "open \"$APP_DIR\""
