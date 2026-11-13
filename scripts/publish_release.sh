#!/bin/zsh
# Publish only when explicitly invoked by the maintainer.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$ROOT_DIR/Resources/Info.plist")"
BUILD="$(plutil -extract CFBundleVersion raw "$ROOT_DIR/Resources/Info.plist")"
UPDATE_DIR="$ROOT_DIR/dist/updates/$BUILD"
CHANNEL="$(plutil -extract JibegazaReleaseChannel raw "$ROOT_DIR/Resources/Info.plist")"
TAG="$(plutil -extract JibegazaReleaseTag raw "$ROOT_DIR/Resources/Info.plist")"
ARCHIVE="$(plutil -extract JibegazaUpdateArchive raw "$ROOT_DIR/Resources/Info.plist")"
ZIP="$UPDATE_DIR/$ARCHIVE"
FEED="$UPDATE_DIR/appcast.xml"
DISPLAY_VERSION="$(plutil -extract JibegazaDisplayVersion raw "$ROOT_DIR/Resources/Info.plist")"
SHARE_ZIP="$ROOT_DIR/dist/Jibegaza MenuBar $DISPLAY_VERSION.zip"
if [[ ! -f "$ZIP" || ! -f "$FEED" || ! -f "$SHARE_ZIP" ]]; then
  echo "First run zsh scripts/build_app.sh --release." >&2
  exit 1
fi
if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI (gh) is required. Install it and run gh auth login." >&2
  exit 1
fi
# Validate that the feed and bundle still describe this build before uploading.
python3 "$ROOT_DIR/scripts/validate_update.py" "$ZIP" "$FEED" "$ROOT_DIR/Resources/Info.plist"
if [[ "$CHANNEL" == "testing" ]]; then
  # A persistent Pre-release holds the testing feed. Unique ZIP names keep the
  # previous feed usable until the new archive has finished uploading.
  NOTES_FILE="$UPDATE_DIR/testing-notes.md"
  COMMIT="$(git -C "$ROOT_DIR" rev-parse HEAD)"
  cat > "$NOTES_FILE" <<NOTES
업데이트 테스트 전용입니다. 정식 Latest와 일반 사용자 앱에는 적용되지 않습니다.

버전: $VERSION / 빌드: $BUILD
소스: https://github.com/ghwaKim/jibegaza_menubar/commit/$COMMIT
NOTES
  if gh release view testing --repo ghwaKim/jibegaza_menubar >/dev/null 2>&1; then
    IS_TESTING="$(gh release view testing --repo ghwaKim/jibegaza_menubar --json isPrerelease,isDraft --jq '.isPrerelease and (.isDraft | not)')"
    if [[ "$IS_TESTING" != "true" ]]; then
      echo "The testing release must be a published Pre-release. Inspect it before retrying." >&2
      exit 1
    fi
    gh release upload testing "$ZIP" --repo ghwaKim/jibegaza_menubar
    gh release upload testing "$SHARE_ZIP" --repo ghwaKim/jibegaza_menubar --clobber
    gh release upload testing "$FEED" --repo ghwaKim/jibegaza_menubar --clobber
    gh release edit testing --repo ghwaKim/jibegaza_menubar --prerelease --latest=false \
      --title "Testing: v$VERSION (build $BUILD)" --notes-file "$NOTES_FILE"
  else
    gh release create testing "$ZIP" "$FEED" "$SHARE_ZIP" --repo ghwaKim/jibegaza_menubar \
      --target "$COMMIT" --title "Testing: v$VERSION (build $BUILD)" \
      --notes-file "$NOTES_FILE" --draft --prerelease --latest=false
    gh release edit testing --repo ghwaKim/jibegaza_menubar --draft=false --prerelease --latest=false
  fi
elif [[ "$CHANNEL" == "stable" ]]; then
  gh release create "$TAG" "$ZIP" "$FEED" "$SHARE_ZIP" \
    --repo ghwaKim/jibegaza_menubar \
    --target "$(git -C "$ROOT_DIR" rev-parse HEAD)" \
    --title "Jibegaza MenuBar v$VERSION" --generate-notes --draft
  gh release edit "$TAG" --repo ghwaKim/jibegaza_menubar --draft=false --latest
else
  echo "Invalid release channel: $CHANNEL" >&2
  exit 1
fi
