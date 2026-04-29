#!/bin/bash
# run-builtin-camera.sh
# 内蔵カメラで sender-mac を実行する便利スクリプト
# X5 がない MacBook でテストする際に使用

set -e

CODEC="${CODEC:-hevc}"
DURATION="${DURATION:-30}"
BITRATE="${BITRATE:-18000000}"
WIDTH="${WIDTH:-2880}"
HEIGHT="${HEIGHT:-1440}"
FPS="${FPS:-30}"

echo "=== sender-mac builtin-camera smoke test ==="
echo "codec: $CODEC"
echo "bitrate: $BITRATE bps"
echo "resolution: ${WIDTH}x${HEIGHT}"
echo "fps: $FPS"
echo "duration: $DURATION seconds"
echo ""

WEBRTC_PROVIDER=livekit swift run sender-mac \
  --builtin-camera \
  --codec "$CODEC" \
  --bitrate "$BITRATE" \
  --width "$WIDTH" \
  --height "$HEIGHT" \
  --fps "$FPS" \
  --duration "$DURATION"
