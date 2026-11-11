#!/bin/zsh
# Publish only when explicitly invoked by the maintainer.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$ROOT_DIR/Resources/Info.plist")"
BUILD="$(plutil -extract CFBundleVersion raw "$ROOT_DIR/Resources/Info.plist")"
UPDATE_DIR="$ROOT_DIR/dist/updates/$BUILD"
ZIP="$UPDATE_DIR/Jibegaza-MenuBar-$VERSION.zip"
FEED="$UPDATE_DIR/appcast.xml"
if [[ ! -f "$ZIP" || ! -f "$FEED" ]]; then
  echo "First run zsh scripts/build_app.sh --release." >&2
  exit 1
fi
if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI (gh) is required. Install it and run gh auth login." >&2
  exit 1
fi
# Validate that the feed and bundle still describe this build before uploading.
python3 "$ROOT_DIR/scripts/validate_update.py" "$ZIP" "$FEED" "$ROOT_DIR/Resources/Info.plist"
gh release create "v$VERSION" "$ZIP" "$FEED" \
  --repo ghwaKim/jibegaza_menubar \
  --target "$(git -C "$ROOT_DIR" rev-parse HEAD)" \
  --title "Jibegaza MenuBar v$VERSION" --generate-notes --draft
# Make the feed discoverable only after both assets have finished uploading.
gh release edit "v$VERSION" --repo ghwaKim/jibegaza_menubar --draft=false --latest
