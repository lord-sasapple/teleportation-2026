#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

SIGNALING_URL="${SIGNALING_URL:-wss://x5-webrtc-signaling.lord-sasapple.workers.dev}"
ROOM_BASE="${ROOM_BASE:-x5-codec-test}"
DURATION="${DURATION:-20}"
DEVICE_NAME="${DEVICE_NAME:-Insta360 X5}"
WIDTH="${WIDTH:-2880}"
HEIGHT="${HEIGHT:-1440}"
FPS="${FPS:-30}"
HEVC_BITRATE="${HEVC_BITRATE:-18000000}"
H264_BITRATE="${H264_BITRATE:-16000000}"
PROVIDER="${WEBRTC_PROVIDER:-livekit}"

run_codec() {
  codec="$1"
  bitrate="$2"
  room="$ROOM_BASE-$codec"

  echo "== $codec test =="
  echo "room=$room signaling=$SIGNALING_URL duration=${DURATION}s bitrate=$bitrate"
  WEBRTC_PROVIDER="$PROVIDER" xcrun swift run sender-mac \
    --device-name "$DEVICE_NAME" \
    --width "$WIDTH" \
    --height "$HEIGHT" \
    --fps "$FPS" \
    --codec "$codec" \
    --bitrate "$bitrate" \
    --signaling-url "$SIGNALING_URL" \
    --room "$room" \
    --duration "$DURATION"
}

WEBRTC_PROVIDER="$PROVIDER" xcrun swift build
run_codec hevc "$HEVC_BITRATE"
run_codec h264 "$H264_BITRATE"

