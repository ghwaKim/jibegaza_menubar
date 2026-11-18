#!/bin/zsh
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
zsh scripts/check_build_sdk.sh
python3 -m unittest discover -s scripts/tests -v
zsh scripts/test.sh
python3 scripts/verify_release_package.py
