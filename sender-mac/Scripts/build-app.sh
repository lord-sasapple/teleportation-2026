#!/bin/bash
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:${PATH:-}"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="${APP_NAME:-SenderMac}"
CONFIGURATION="${CONFIGURATION:-debug}"
WEBRTC_PROVIDER="${WEBRTC_PROVIDER:-livekit}"
APP_DIR="$ROOT_DIR/.build/app/${APP_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"

cd "$ROOT_DIR"

WEBRTC_PROVIDER="$WEBRTC_PROVIDER" /usr/bin/xcrun swift build -c "$CONFIGURATION" >&2

mkdir -p "$MACOS_DIR" "$FRAMEWORKS_DIR"
/bin/cp "$ROOT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
/bin/cp "$ROOT_DIR/.build/$CONFIGURATION/sender-mac" "$MACOS_DIR/$APP_NAME"
/bin/chmod +x "$MACOS_DIR/$APP_NAME"

if [[ "$WEBRTC_PROVIDER" == "livekit" ]]; then
  FRAMEWORK_SOURCE="$ROOT_DIR/.build/arm64-apple-macosx/$CONFIGURATION/LiveKitWebRTC.framework"
  if [[ ! -d "$FRAMEWORK_SOURCE" ]]; then
    FRAMEWORK_SOURCE="$(/usr/bin/find "$ROOT_DIR/.build/artifacts" -path '*macos-arm64_x86_64/LiveKitWebRTC.framework' -type d | /usr/bin/head -1)"
  fi

  if [[ -z "${FRAMEWORK_SOURCE:-}" || ! -d "$FRAMEWORK_SOURCE" ]]; then
    echo "LiveKitWebRTC.framework が見つかりません" >&2
    exit 1
  fi

  /bin/rm -rf "$FRAMEWORKS_DIR/LiveKitWebRTC.framework"
  /bin/cp -R "$FRAMEWORK_SOURCE" "$FRAMEWORKS_DIR/LiveKitWebRTC.framework"

  if ! /usr/bin/otool -l "$MACOS_DIR/$APP_NAME" | /usr/bin/grep -q '@executable_path/../Frameworks'; then
    /usr/bin/install_name_tool -add_rpath '@executable_path/../Frameworks' "$MACOS_DIR/$APP_NAME"
  fi
fi

/usr/bin/codesign --force --deep --sign - "$APP_DIR" >/dev/null

echo "$APP_DIR"
