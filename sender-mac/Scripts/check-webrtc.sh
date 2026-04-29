#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FRAMEWORK_PATH="$ROOT_DIR/ThirdParty/WebRTC/WebRTC.xcframework"
PROVIDER="${WEBRTC_PROVIDER:-local}"

if [ "$PROVIDER" = "livekit" ]; then
  echo "WEBRTC_PROVIDER=livekit"
  echo "SwiftPM will use https://github.com/livekit/webrtc-xcframework.git"
  echo "Product: LiveKitWebRTC"
  echo "Symbols are LKRTC* prefixed."
elif [ -d "$FRAMEWORK_PATH" ]; then
  echo "WebRTC.xcframework found: $FRAMEWORK_PATH"
  echo "SwiftPM will build with HAS_WEBRTC."
else
  echo "WebRTC.xcframework not found."
  echo "Expected path: $FRAMEWORK_PATH"
  echo "SwiftPM will build with the explicit WebRTC stub adapter."
fi
