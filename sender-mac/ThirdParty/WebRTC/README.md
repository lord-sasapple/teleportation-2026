# WebRTC.xcframework

Place the macOS-compatible libwebrtc framework here when enabling native WebRTC.

Expected path:

```text
sender-mac/ThirdParty/WebRTC/WebRTC.xcframework
```

The Swift package detects this path at build time. If it exists, `Package.swift` adds a `WebRTC` binary target and defines `HAS_WEBRTC`. If it does not exist, the sender still builds and runs with the explicit stub adapter.

## Current status

The repo does not vendor libwebrtc binaries. The framework is large, platform-specific, and should be supplied through a deliberate dependency process rather than committed casually.

Next implementation step after placing `WebRTC.xcframework`:

1. Instantiate `RTCPeerConnectionFactory`.
2. Create sender `RTCPeerConnection`.
3. Add ICE server config.
4. Create DataChannel for frame timestamps.
5. Create offer when receiver joins.
6. Send local SDP and ICE through signaling-worker.
7. Apply HEVC/H.265 first codec preference, keeping H.264 fallback.
8. Connect encoded frame path to the chosen libwebrtc video source or encoder integration path.

