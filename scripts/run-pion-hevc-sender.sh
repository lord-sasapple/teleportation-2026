#!/bin/bash
set -euo pipefail

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:${PATH:-}"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SIGNALING_URL="${SIGNALING_URL:-wss://x5-webrtc-signaling.lord-sasapple.workers.dev}"
ROOM="${1:-${ROOM:-}}"
DURATION="${DURATION:-600}"
WIDTH="${WIDTH:-2880}"
HEIGHT="${HEIGHT:-1440}"
FPS="${FPS:-30}"
BITRATE="${BITRATE:-6000000}"
QUEUE_SIZE="${QUEUE_SIZE:-3}"
PION_FRAME_SOCKET="${PION_FRAME_SOCKET:-127.0.0.1:5005}"
WEBRTC_PROVIDER="${WEBRTC_PROVIDER:-livekit}"
DEVICE_ID="${DEVICE_ID:-}"
USE_BUILTIN_CAMERA="${USE_BUILTIN_CAMERA:-0}"
REQUIRE_ASPECT_RATIO="${REQUIRE_ASPECT_RATIO:-2:1}"
CLEAN_STALE_FRAME_LISTENER="${CLEAN_STALE_FRAME_LISTENER:-1}"

if [[ -z "$ROOM" ]]; then
  echo "usage: ./scripts/run-pion-hevc-sender.sh <room-id>"
  echo "example: ./scripts/run-pion-hevc-sender.sh pion-masato-wan-001"
  exit 64
fi

cleanup() {
  if [[ -n "${PION_PID:-}" ]] && kill -0 "$PION_PID" >/dev/null 2>&1; then
    kill "$PION_PID" >/dev/null 2>&1 || true
    wait "$PION_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

FRAME_PORT="${PION_FRAME_SOCKET##*:}"
if [[ "$CLEAN_STALE_FRAME_LISTENER" == "1" ]] && command -v lsof >/dev/null 2>&1; then
  STALE_PIDS="$(lsof -tiTCP:"$FRAME_PORT" -sTCP:LISTEN 2>/dev/null || true)"
  if [[ -n "$STALE_PIDS" ]]; then
    echo "stopping stale frame listener(s) on $PION_FRAME_SOCKET: $STALE_PIDS"
    kill $STALE_PIDS >/dev/null 2>&1 || true
    sleep 1
  fi
  STILL_LISTENING="$(lsof -tiTCP:"$FRAME_PORT" -sTCP:LISTEN 2>/dev/null || true)"
  if [[ -n "$STILL_LISTENING" ]]; then
    echo "error: $PION_FRAME_SOCKET is still in use by PID(s): $STILL_LISTENING"
    echo "try: kill $STILL_LISTENING"
    exit 1
  fi
fi

echo "== Teleportation Pion HEVC sender =="
echo "room=$ROOM"
echo "signaling=$SIGNALING_URL"
echo "frames=$PION_FRAME_SOCKET queue-size=$QUEUE_SIZE"
echo "codec=hevc ${WIDTH}x${HEIGHT}@${FPS}fps bitrate=$BITRATE duration=${DURATION}s aspect=$REQUIRE_ASPECT_RATIO"

(
  cd "$ROOT_DIR/tools/pion-hevc-sender"
  go run . \
    --room "$ROOM" \
    --signaling-url "$SIGNALING_URL" \
    --duration "$DURATION" \
    --listen-frames "$PION_FRAME_SOCKET" \
    --fps "$FPS" \
    --queue-size "$QUEUE_SIZE"
) &
PION_PID=$!

sleep 2
if ! kill -0 "$PION_PID" >/dev/null 2>&1; then
  wait "$PION_PID"
fi

SENDER_ARGS=(
  --codec hevc
  --width "$WIDTH"
  --height "$HEIGHT"
  --require-aspect-ratio "$REQUIRE_ASPECT_RATIO"
  --fps "$FPS"
  --bitrate "$BITRATE"
  --duration "$DURATION"
  --log-every 30
  --pion-frame-socket "$PION_FRAME_SOCKET"
)

if [[ "$USE_BUILTIN_CAMERA" == "1" ]]; then
  SENDER_ARGS+=(--builtin-camera)
elif [[ -n "$DEVICE_ID" ]]; then
  SENDER_ARGS+=(--device-id "$DEVICE_ID")
fi

cd "$ROOT_DIR/sender-mac"
WEBRTC_PROVIDER="$WEBRTC_PROVIDER" /usr/bin/xcrun swift run sender-mac "${SENDER_ARGS[@]}"
