#!/bin/bash
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:${PATH:-}"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$(WEBRTC_PROVIDER="${WEBRTC_PROVIDER:-livekit}" "$ROOT_DIR/Scripts/build-app.sh")"

echo "== SenderMac.app camera permission =="
echo "app=$APP_PATH"
/usr/bin/tccutil reset Camera com.telepresence.sender-mac >/dev/null 2>&1 || true
/usr/bin/open -W -n "$APP_PATH" --args --request-camera-permission
