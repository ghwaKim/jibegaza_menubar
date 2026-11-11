#!/bin/zsh
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if (( $# != 1 )); then
  echo "Usage: zsh scripts/setup_updates.sh <public-key>" >&2
  echo "Generate and keep the private key in your personal environment. Pass only its public key here." >&2
  exit 2
fi
PUBLIC_KEY="$1"
python3 - "$PUBLIC_KEY" <<'CHECK'
import base64, sys
if len(base64.b64decode(sys.argv[1], validate=True)) != 32:
    raise SystemExit("Expected a base64-encoded 32-byte Ed25519 public key")
CHECK
EXISTING_KEY=""
# plutil can print missing-key diagnostics to stdout; only capture successful reads.
if plutil -extract SUPublicEDKey raw "$ROOT_DIR/Resources/Info.plist" >/dev/null 2>&1; then
  EXISTING_KEY="$(plutil -extract SUPublicEDKey raw "$ROOT_DIR/Resources/Info.plist")"
fi
if [[ -n "$EXISTING_KEY" && "$EXISTING_KEY" != "$PUBLIC_KEY" ]]; then
  echo "Refusing to replace the app's existing public key. Restore the original signing key." >&2
  exit 1
fi
plutil -replace SUPublicEDKey -string "$PUBLIC_KEY" "$ROOT_DIR/Resources/Info.plist"
echo "Public key configured. No private key was created or stored."
