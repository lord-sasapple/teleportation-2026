#!/bin/bash
set -euo pipefail

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:${PATH:-}"

REPO_URL="${REPO_URL:-https://github.com/lord-sasapple/teleportation-2026.git}"
TARGET_DIR="${TELEPORTATION_DIR:-$HOME/teleportation-2026}"
SIGNALING_URL="${SIGNALING_URL:-wss://x5-webrtc-signaling.lord-sasapple.workers.dev}"
ROOM="${1:-${ROOM:-}}"
DURATION="${DURATION:-600}"
CODEC="${CODEC:-h264}"
WEBRTC_PROVIDER="${WEBRTC_PROVIDER:-livekit}"
ICE_SERVER="${ICE_SERVER:-stun:stun.l.google.com:19302}"

if [[ -z "$ROOM" ]]; then
  echo "usage: bash run-remote-receiver.sh <room-id>"
  echo "example: bash run-remote-receiver.sh test-room-001"
  exit 64
fi

if ! command -v git >/dev/null 2>&1; then
  echo "git が見つかりません。先に Command Line Tools を入れてください:"
  echo "  xcode-select --install"
  exit 1
fi

if ! xcode-select -p >/dev/null 2>&1; then
  echo "Xcode Command Line Tools が見つかりません。以下を実行してからもう一度試してください:"
  echo "  xcode-select --install"
  exit 1
fi

echo "== Teleportation remote receiver =="
echo "target=$TARGET_DIR"
echo "room=$ROOM"
echo "signaling=$SIGNALING_URL"
echo "codec=$CODEC duration=${DURATION}s"

if [[ -d "$TARGET_DIR/.git" ]]; then
  echo "[1/3] Updating repo"
  git -C "$TARGET_DIR" pull --ff-only
else
  echo "[1/3] Cloning repo"
  git clone "$REPO_URL" "$TARGET_DIR"
fi

cd "$TARGET_DIR/receiver-mac"

echo "[2/3] Building receiver-mac if needed"
WEBRTC_PROVIDER="$WEBRTC_PROVIDER" swift build

echo "[3/3] Starting receiver-mac"
echo "Keep this terminal open. Close the receiver window or press Ctrl-C to stop."
WEBRTC_PROVIDER="$WEBRTC_PROVIDER" \
SIGNALING_URL="$SIGNALING_URL" \
ROOM="$ROOM" \
CODEC="$CODEC" \
SIGNALING_ONLY=0 \
DURATION="$DURATION" \
ICE_SERVER="$ICE_SERVER" \
bash ./Scripts/run-receiver-signaling.sh
