#!/bin/zsh
set -euo pipefail

# System control appearance depends on the SDK linked into the executable.
# Keep local app packages and CI releases on the same SDK.
EXPECTED_SDK="26.5"
ACTUAL_SDK="$(xcrun --sdk macosx --show-sdk-version)"
echo "macOS SDK: $ACTUAL_SDK (required: $EXPECTED_SDK)"
if [[ "$ACTUAL_SDK" != "$EXPECTED_SDK" ]]; then
  echo "Use Xcode 26.5 or Command Line Tools with macOS SDK $EXPECTED_SDK before packaging." >&2
  exit 1
fi
