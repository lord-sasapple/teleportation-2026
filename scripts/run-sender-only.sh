#!/bin/bash
set -euo pipefail

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:${PATH:-}"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SIGNALING_URL="${SIGNALING_URL:-wss://x5-webrtc-signaling.lord-sasapple.workers.dev}"
ROOM="${1:-${ROOM:-}}"
DURATION="${DURATION:-600}"
CODEC="${CODEC:-h264}"
WIDTH="${WIDTH:-1280}"
HEIGHT="${HEIGHT:-720}"
FPS="${FPS:-30}"
BITRATE="${BITRATE:-4000000}"
WEBRTC_PROVIDER="${WEBRTC_PROVIDER:-livekit}"
RUN_SENDER_AS_APP="${RUN_SENDER_AS_APP:-1}"

if [[ -z "$ROOM" ]]; then
  echo "usage: ./scripts/run-sender-only.sh <room-id>"
  echo "example: ./scripts/run-sender-only.sh test-room-001"
  exit 64
fi

cleanup() {
  /usr/bin/pkill -f "SenderMac.app/Contents/MacOS/SenderMac" >/dev/null 2>&1 || true
  /usr/bin/pkill -f "/SenderMac " >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

echo "== Teleportation sender-only =="
echo "room=$ROOM"
echo "signaling=$SIGNALING_URL"
echo "codec=$CODEC ${WIDTH}x${HEIGHT}@${FPS}fps bitrate=$BITRATE duration=${DURATION}s"

cd "$ROOT_DIR/sender-mac"

if [[ "$RUN_SENDER_AS_APP" == "1" ]]; then
  APP_PATH="$(WEBRTC_PROVIDER="$WEBRTC_PROVIDER" ./Scripts/build-app.sh)"
  SENDER_STDOUT="/tmp/sender-mac-${ROOM}.out"
  SENDER_STDERR="/tmp/sender-mac-${ROOM}.err"
  /bin/rm -f "$SENDER_STDOUT" "$SENDER_STDERR"
  echo "sender app=$APP_PATH"
  /usr/bin/open -W -n "$APP_PATH" --stdout "$SENDER_STDOUT" --stderr "$SENDER_STDERR" --args \
    --builtin-camera \
    --codec "$CODEC" \
    --width "$WIDTH" \
    --height "$HEIGHT" \
    --fps "$FPS" \
    --bitrate "$BITRATE" \
    --signaling-url "$SIGNALING_URL" \
    --room "$ROOM" \
    --duration "$DURATION" \
    --log-every 30

  echo "== sender stdout =="
  /bin/cat "$SENDER_STDOUT" 2>/dev/null || true
  echo "== sender stderr =="
  /bin/cat "$SENDER_STDERR" 2>/dev/null || true
else
  WEBRTC_PROVIDER="$WEBRTC_PROVIDER" /usr/bin/xcrun swift run sender-mac \
    --builtin-camera \
    --codec "$CODEC" \
    --width "$WIDTH" \
    --height "$HEIGHT" \
    --fps "$FPS" \
    --bitrate "$BITRATE" \
    --signaling-url "$SIGNALING_URL" \
    --room "$ROOM" \
    --duration "$DURATION" \
    --log-every 30
fi
