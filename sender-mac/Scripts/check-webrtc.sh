#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FRAMEWORK_PATH="$ROOT_DIR/ThirdParty/WebRTC/WebRTC.xcframework"

if [ -d "$FRAMEWORK_PATH" ]; then
  echo "WebRTC.xcframework found: $FRAMEWORK_PATH"
  echo "SwiftPM will build with HAS_WEBRTC."
else
  echo "WebRTC.xcframework not found."
  echo "Expected path: $FRAMEWORK_PATH"
  echo "SwiftPM will build with the explicit WebRTC stub adapter."
fi

