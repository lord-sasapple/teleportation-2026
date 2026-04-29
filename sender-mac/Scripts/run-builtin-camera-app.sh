#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$(WEBRTC_PROVIDER="${WEBRTC_PROVIDER:-livekit}" "$ROOT_DIR/Scripts/build-app.sh")"

CODEC="${CODEC:-h264}"
DURATION="${DURATION:-20}"
BITRATE="${BITRATE:-4000000}"
WIDTH="${WIDTH:-1280}"
HEIGHT="${HEIGHT:-720}"
FPS="${FPS:-30}"
SIGNALING_URL="${SIGNALING_URL:-wss://x5-webrtc-signaling.lord-sasapple.workers.dev}"
ROOM="${ROOM:-mac-builtin-$(date +%s)}"

ARGS=(
  --builtin-camera
  --codec "$CODEC"
  --bitrate "$BITRATE"
  --width "$WIDTH"
  --height "$HEIGHT"
  --fps "$FPS"
  --signaling-url "$SIGNALING_URL"
  --room "$ROOM"
  --duration "$DURATION"
  --log-every 30
)

echo "== SenderMac.app builtin-camera run =="
echo "app=$APP_PATH"
echo "room=$ROOM signaling=$SIGNALING_URL codec=$CODEC ${WIDTH}x${HEIGHT}@${FPS}fps duration=${DURATION}s"
echo "カメラ許可ダイアログを出すため LaunchServices 経由で起動します"

/usr/bin/open -W -n "$APP_PATH" --args "${ARGS[@]}"
