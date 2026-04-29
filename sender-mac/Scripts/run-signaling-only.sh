#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

SIGNALING_URL="${SIGNALING_URL:-wss://x5-webrtc-signaling.lord-sasapple.workers.dev}"
ROOM="${ROOM:-x5-sender-signaling-smoke}"
DURATION="${DURATION:-5}"
PROVIDER="${WEBRTC_PROVIDER:-livekit}"

echo "== sender signaling-only smoke =="
echo "room=$ROOM signaling=$SIGNALING_URL duration=${DURATION}s provider=$PROVIDER"

WEBRTC_PROVIDER="$PROVIDER" xcrun swift run sender-mac \
  --signaling-only \
  --signaling-url "$SIGNALING_URL" \
  --room "$ROOM" \
  --duration "$DURATION"
