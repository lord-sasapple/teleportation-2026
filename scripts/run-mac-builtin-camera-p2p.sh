#!/bin/bash
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:${PATH:-}"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOM="${ROOM:-mac-builtin-$(date +%s)}"
SIGNALING_URL="${SIGNALING_URL:-wss://x5-webrtc-signaling.lord-sasapple.workers.dev}"
DURATION="${DURATION:-20}"
CODEC="${CODEC:-h264}"
WIDTH="${WIDTH:-1280}"
HEIGHT="${HEIGHT:-720}"
FPS="${FPS:-30}"
BITRATE="${BITRATE:-4000000}"
WEBRTC_PROVIDER="${WEBRTC_PROVIDER:-livekit}"
RUN_SENDER_AS_APP="${RUN_SENDER_AS_APP:-1}"

echo "== Mac built-in camera P2P smoke =="
echo "room=$ROOM"
echo "signaling=$SIGNALING_URL"
echo "codec=$CODEC ${WIDTH}x${HEIGHT}@${FPS}fps bitrate=$BITRATE duration=${DURATION}s"

(
  cd "$ROOT_DIR/receiver-mac"
  WEBRTC_PROVIDER="$WEBRTC_PROVIDER" \
  SIGNALING_URL="$SIGNALING_URL" \
  ROOM="$ROOM" \
  CODEC="$CODEC" \
  SIGNALING_ONLY=0 \
  DURATION="$((DURATION + 6))" \
  ./Scripts/run-receiver-signaling.sh
) &
RECEIVER_PID=$!

cleanup() {
  if kill -0 "$RECEIVER_PID" >/dev/null 2>&1; then
    kill "$RECEIVER_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

sleep 4

cd "$ROOT_DIR/sender-mac"
if [[ "$RUN_SENDER_AS_APP" == "1" ]]; then
  APP_PATH="$(WEBRTC_PROVIDER="$WEBRTC_PROVIDER" ./Scripts/build-app.sh)"
  echo "sender app=$APP_PATH"
  /usr/bin/open -W -n "$APP_PATH" --args \
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

wait "$RECEIVER_PID"
