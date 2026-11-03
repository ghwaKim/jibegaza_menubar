#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEVELOPER_DIR_PATH="$(xcode-select -p)"
TESTING_DIR="$DEVELOPER_DIR_PATH/Library/Developer"

# Command Line Tools ships Swift Testing outside the default framework paths.
if [[ "$DEVELOPER_DIR_PATH" == */CommandLineTools && -d "$TESTING_DIR/Frameworks/Testing.framework" ]]; then
    swift test --package-path "$ROOT_DIR" \
        -Xswiftc -F -Xswiftc "$TESTING_DIR/Frameworks" \
        -Xlinker "-F$TESTING_DIR/Frameworks" \
        -Xlinker -rpath -Xlinker "$TESTING_DIR/Frameworks" \
        -Xlinker -rpath -Xlinker "$TESTING_DIR/usr/lib" "$@"
else
    swift test --package-path "$ROOT_DIR" "$@"
fi
