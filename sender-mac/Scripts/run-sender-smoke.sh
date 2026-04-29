#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "== WebRTC provider =="
./Scripts/check-webrtc.sh

echo "== Swift build =="
WEBRTC_PROVIDER="${WEBRTC_PROVIDER:-livekit}" xcrun swift build

echo "== Device list =="
WEBRTC_PROVIDER="${WEBRTC_PROVIDER:-livekit}" xcrun swift run sender-mac --list-devices

