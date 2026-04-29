#!/bin/bash
# Helper to run receiver-mac with low-latency defaults.
set -e

SIGNALING_URL=${SIGNALING_URL:-ws://127.0.0.1:8787}
ROOM=${ROOM:-x5-test-room}
DURATION=${DURATION:-30}
CODEC=${CODEC:-hevc}
WEBRTC_PROVIDER=${WEBRTC_PROVIDER:-livekit}
SIGNALING_ONLY=${SIGNALING_ONLY:-1}
ICE_SERVER=${ICE_SERVER:-stun:stun.l.google.com:19302}

cd "$(dirname "$0")/.."

ARGS=(--signaling-url "$SIGNALING_URL" --room "$ROOM" --codec "$CODEC" --duration "$DURATION" --ice-server "$ICE_SERVER")

if [[ "$SIGNALING_ONLY" == "1" ]]; then
	ARGS+=(--signaling-only)
fi

WEBRTC_PROVIDER="$WEBRTC_PROVIDER" swift run receiver-mac "${ARGS[@]}"
