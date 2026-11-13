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
    echo "--release: create signed updates using the selected RELEASE_CHANNEL (stable/testing)"
    echo "RELEASE_CHANNEL=testing --test: create a bootstrap test app with the next display version"
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
if [[ "$BUILD_MODE" == "release" ]] && ! plutil -extract SUPublicEDKey raw "$INFO_PLIST_PATH" >/dev/null 2>&1; then
  echo "Run zsh scripts/setup_updates.sh <public-key> before creating an update-enabled release." >&2
  exit 1
fi
if [[ "$BUILD_MODE" == "release" && ( -z "${SPARKLE_PRIVATE_KEY_FILE:-}" || ! -r "${SPARKLE_PRIVATE_KEY_FILE:-}" ) ]]; then
  echo "Set SPARKLE_PRIVATE_KEY_FILE to a readable external Sparkle private-key file." >&2
  exit 1
fi
RELEASE_CHANNEL="${RELEASE_CHANNEL:-stable}"
APP_VERSION="$CURRENT_VERSION"
BUILD_NUMBER="$CURRENT_BUILD"
NEXT_PLIST="$LOCK_DIR/Info.plist"
cp "$INFO_PLIST_PATH" "$NEXT_PLIST"
if [[ "$BUILD_MODE" == "release" ]]; then
  APP_VERSION="${RELEASE_VERSION:-${CURRENT_VERSION%.*}.$(( ${CURRENT_VERSION##*.} + 1 ))}"
  BUILD_NUMBER="${RELEASE_BUILD_NUMBER:-$(( CURRENT_BUILD + 1 ))}"
  python3 - "$ROOT_DIR" "$APP_VERSION" "$BUILD_NUMBER" "$CURRENT_VERSION" "$CURRENT_BUILD" <<'CHECK'
import sys
sys.path.insert(0, sys.argv[1] + "/scripts")
from check_release import validate_numbers
validate_numbers(*sys.argv[2:])
CHECK
  plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$NEXT_PLIST"
  plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$NEXT_PLIST"
fi
# --test can create an update-capable bootstrap app without a private key.
if [[ "$BUILD_MODE" == "test" && "$RELEASE_CHANNEL" == "testing" ]]; then
  APP_VERSION="${RELEASE_VERSION:-${CURRENT_VERSION%.*}.$(( ${CURRENT_VERSION##*.} + 1 ))}"
  BUILD_NUMBER="${RELEASE_BUILD_NUMBER:-$CURRENT_BUILD}"
fi
python3 - "$ROOT_DIR" "$NEXT_PLIST" "$APP_VERSION" "$BUILD_NUMBER" "$RELEASE_CHANNEL" "$BUILD_MODE" <<'CONFIG'
import plistlib, sys
sys.path.insert(0, sys.argv[1] + "/scripts")
from check_release import version_tuple
from release_config import release_config, display_label
path, version, build, channel, build_mode = sys.argv[2:]
version_tuple(version)
if not build.isdecimal() or int(build) <= 0:
    raise SystemExit("Invalid build number")
config = release_config(version, build, channel)
with open(path, "rb") as f:
    info = plistlib.load(f)
info.update(CFBundleShortVersionString=version, CFBundleVersion=build,
            SUFeedURL=config["feed"], JibegazaReleaseChannel=channel, JibegazaBuildMode=build_mode,
            JibegazaReleaseTag=config["tag"], JibegazaUpdateArchive=config["archive"],
            JibegazaDisplayVersion=display_label(version, channel, build_mode))
with open(path, "wb") as f:
    plistlib.dump(info, f)
CONFIG
RELEASE_TAG="$(plutil -extract JibegazaReleaseTag raw "$NEXT_PLIST")"
UPDATE_ARCHIVE="$(plutil -extract JibegazaUpdateArchive raw "$NEXT_PLIST")"
APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
RELEASE_BINARY="$ROOT_DIR/.build/release/$EXECUTABLE_NAME"
DISPLAY_VERSION="$(plutil -extract JibegazaDisplayVersion raw "$NEXT_PLIST")"
ZIP_PATH="$OUTPUT_DIR/$APP_NAME $DISPLAY_VERSION.zip"
ICON_PATH="$ROOT_DIR/Resources/AppIcon.icns"
EXPORT_IMAGE_PATH="$ROOT_DIR/Assets/Export/앱_설치_가이드.png"
DIST_EXPORT_IMAGE_PATH="$OUTPUT_DIR/앱_설치_가이드.png"
PACKAGE_DIR="$OUTPUT_DIR/$APP_NAME Package"

echo "Building $BUILD_MODE package, version $APP_VERSION (build $BUILD_NUMBER)..."
swift build -c release --package-path "$ROOT_DIR"

if [[ ! -f "$RELEASE_BINARY" ]]; then
  echo "Release binary not found: $RELEASE_BINARY" >&2
  exit 1
fi

SPARKLE_DIR="$ROOT_DIR/.build/artifacts/sparkle/Sparkle"
SPARKLE_FRAMEWORK="$SPARKLE_DIR/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
  echo "Sparkle framework not found: $SPARKLE_FRAMEWORK" >&2
  exit 1
fi

echo "Assembling app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

mkdir -p "$CONTENTS_DIR/Frameworks"
ditto "$SPARKLE_FRAMEWORK" "$CONTENTS_DIR/Frameworks/Sparkle.framework"
cp "$SPARKLE_DIR/LICENSE" "$RESOURCES_DIR/Sparkle-LICENSE.txt"

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
  codesign --force --sign - "$APP_DIR"
  codesign --verify --deep --strict "$APP_DIR"
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
  # Publish an app-only ZIP: the human installation instructions are kept in the sharing ZIP above.
  UPDATE_DIR="$OUTPUT_DIR/updates/$BUILD_NUMBER"
  mkdir -p "$UPDATE_DIR"
  UPDATE_ZIP="$UPDATE_DIR/$UPDATE_ARCHIVE"
  ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$UPDATE_ZIP"
  "$SPARKLE_DIR/bin/generate_appcast" \
    --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" \
    --download-url-prefix "https://github.com/ghwaKim/jibegaza_menubar/releases/download/$RELEASE_TAG/" \
    "$UPDATE_DIR"
  python3 "$ROOT_DIR/scripts/validate_update.py" "$UPDATE_ZIP" "$UPDATE_DIR/appcast.xml" "$NEXT_PLIST"
  echo "Upload both files in $UPDATE_DIR to GitHub Release $RELEASE_TAG."
  mv "$NEXT_PLIST" "$INFO_PLIST_PATH"
fi

echo
echo "Done."
echo "App: $APP_DIR"
echo "Zip: $ZIP_PATH"
echo
echo "Run it with:"
echo "open \"$APP_DIR\""
