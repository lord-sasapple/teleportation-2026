# receiver-quest

Quest 3 上で動く Unity 受信アプリの予定地です。今回の初期タスクでは本格実装せず、設計と TODO だけを残します。

## 方針

- Unity Quest 3 app として実装します。
- libwebrtc Android で WebRTC 1:1 P2P 映像を受信します。
- MediaCodec HEVC/H.265 hardware decode を使う前提です。
- H.264 fallback を必ず残します。
- 受信した equirectangular texture を inside-out sphere に貼ります。
- OpenXR で HMD 内に 360 度表示します。
- Cloudflare signaling-worker へ WebSocket 接続し、SDP / ICE candidate を交換します。
- DataChannel で `frame-timestamp` を受け取ります。
- stats overlay を表示します。
- 実際の decoder 名を表示します。
- software decode fallback を検出したら警告します。

## Receiver latency report

```json
{
  "type": "frame-latency-report",
  "sequence": 100,
  "captureTimeMs": 1710000000000,
  "encodeEndTimeMs": 1710000000012,
  "receiverDataTimeMs": 1710000000040,
  "firstFrameSeenTimeMs": 1710000000055,
  "renderSubmitTimeMs": 1710000000066,
  "estimatedAppLatencyMs": 66
}
```

## 後続 TODO

詳細は [TODO.md](TODO.md) を参照してください。

