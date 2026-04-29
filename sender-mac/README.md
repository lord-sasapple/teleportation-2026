# sender-mac

MacBook M3 上で動く Swift macOS 送信アプリの予定地です。今回の初期タスクでは本格実装せず、設計と TODO だけを残します。

## 方針

- Swift macOS app として実装します。
- AVFoundation で Insta360 X5 を UVC カメラとして取得します。
- 想定入力は 2880x1440 / 30fps / 2:1 equirectangular です。
- VideoToolbox で HEVC/H.265 low-latency hardware encode を行います。
- H.264 fallback encoder を必ず残します。
- libwebrtc native で Quest 3 へ WebRTC 1:1 P2P 送信します。
- Cloudflare signaling-worker へ WebSocket 接続し、SDP / ICE candidate を交換します。
- DataChannel で `frame-timestamp` を receiver へ送ります。
- capture 時間、encode 時間、send 時間を測ります。
- WebRTC stats を定期取得してログに出します。

## DataChannel timestamp

```json
{
  "type": "frame-timestamp",
  "sequence": 100,
  "captureTimeMs": 1710000000000,
  "encodeStartTimeMs": 1710000000005,
  "encodeEndTimeMs": 1710000000012,
  "sendTimeMs": 1710000000014
}
```

## 後続 TODO

詳細は [TODO.md](TODO.md) を参照してください。

