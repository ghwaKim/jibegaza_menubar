#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Jibegaza MenuBar"
EXECUTABLE_NAME="TimeCalculatorMenuBar"
INFO_PLIST_PATH="$ROOT_DIR/Resources/Info.plist"
if (( $# > 1 )); then
  echo "Usage: zsh scripts/build_app.sh [--test|--release]" >&2
  exit 2
fi
case "${1:---test}" in
  --test) BUILD_MODE="test" ;;
  --release) BUILD_MODE="release" ;;
  -h|--help)
    echo "Usage: zsh scripts/build_app.sh [--test|--release]"
    echo "Default: --test (keep the current version, write to dist/test)"
    echo "--release: increment the version and build number, write to dist"
    exit 0
    ;;
  *)
    echo "Usage: zsh scripts/build_app.sh [--test|--release]" >&2
    exit 2
    ;;
esac

OUTPUT_DIR="$ROOT_DIR/dist"
if [[ "$BUILD_MODE" == "test" ]]; then
  OUTPUT_DIR="$OUTPUT_DIR/test"
fi
mkdir -p "$OUTPUT_DIR"
LOCK_DIR="$ROOT_DIR/dist/.build-app.lock"
if ! mkdir "$LOCK_DIR"; then
  echo "Another app build is in progress: $LOCK_DIR" >&2
  exit 1
fi
trap 'rm -rf "$LOCK_DIR"' EXIT

CURRENT_VERSION="$(plutil -extract CFBundleShortVersionString raw "$INFO_PLIST_PATH")"
CURRENT_BUILD="$(plutil -extract CFBundleVersion raw "$INFO_PLIST_PATH")"
if [[ ! "$CURRENT_VERSION" =~ '^[0-9]+\.[0-9]+$' || ! "$CURRENT_BUILD" =~ '^[0-9]+$' ]]; then
  echo "Expected a major.minor version and a numeric build number in $INFO_PLIST_PATH" >&2
  exit 1
fi
APP_VERSION="$CURRENT_VERSION"
BUILD_NUMBER="$CURRENT_BUILD"
NEXT_PLIST="$LOCK_DIR/Info.plist"
cp "$INFO_PLIST_PATH" "$NEXT_PLIST"
if [[ "$BUILD_MODE" == "release" ]]; then
  APP_VERSION="${CURRENT_VERSION%.*}.$(( ${CURRENT_VERSION##*.} + 1 ))"
  BUILD_NUMBER="$(( CURRENT_BUILD + 1 ))"
  plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$NEXT_PLIST"
  plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$NEXT_PLIST"
fi
APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
RELEASE_BINARY="$ROOT_DIR/.build/release/$EXECUTABLE_NAME"
ZIP_PATH="$OUTPUT_DIR/$APP_NAME v$APP_VERSION.zip"
ICON_PATH="$ROOT_DIR/Resources/AppIcon.icns"
EXPORT_IMAGE_PATH="$ROOT_DIR/Assets/Export/앱_실행_방법.png"
DIST_EXPORT_IMAGE_PATH="$OUTPUT_DIR/앱_실행_방법.png"
PACKAGE_DIR="$OUTPUT_DIR/$APP_NAME Package"

echo "Building $BUILD_MODE package, version $APP_VERSION (build $BUILD_NUMBER)..."
swift build -c release --package-path "$ROOT_DIR"

if [[ ! -f "$RELEASE_BINARY" ]]; then
  echo "Release binary not found: $RELEASE_BINARY" >&2
  exit 1
fi

echo "Assembling app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$NEXT_PLIST" "$CONTENTS_DIR/Info.plist"
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
if [[ "$BUILD_MODE" == "release" ]]; then
  mv "$NEXT_PLIST" "$INFO_PLIST_PATH"
fi

echo
echo "Done."
echo "App: $APP_DIR"
echo "Zip: $ZIP_PATH"
echo
echo "Run it with:"
echo "open \"$APP_DIR\""
