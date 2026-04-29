# sender-mac

MacBook M3 上で X5 の UVC 映像を取得し、VideoToolbox で HEVC/H.265 または H.264 に低遅延エンコードする sender 側の土台です。

現時点では SwiftPM の実行ファイルとして実装しています。Xcode の `.app` bundle 化、libwebrtc native 組み込み、DataChannel 送信は後続タスクです。

## できること

- AVFoundation で video device を列挙する。
- X5 らしい device を `localizedName` から選択する。
- `--device-id` または `--device-name` で明示選択する。
- 2880x1440 / 30fps の format を選択する。
- `AVCaptureSession` で NV12 `CVPixelBuffer` を受ける。
- 各 frame に sequence と capture timestamp を付ける。
- VideoToolbox の HEVC/H.265 hardware encoder を作る。
- H.264 fallback encoder を選択できる。
- realtime encode と frame reordering off を設定する。
- capture/encode timing、encoded size、keyframe を日本語ログで出す。
- signaling-worker へ sender role で WebSocket 接続し、`join` / `ping` / `leave` を送る。
- signaling-worker から `joined` / `peer-joined` / `answer` / `ice-candidate` / `peer-left` / `error` を型付きで処理する。
- WebRTC adapter 境界を用意し、raw `CVPixelBuffer` と frame timestamp を渡す。
- DataChannel 用 `frame-timestamp` JSON を生成する。
- `ThirdParty/WebRTC/WebRTC.xcframework` が存在する時だけ SwiftPM が `HAS_WEBRTC` を有効にする。
- `HAS_WEBRTC` 有効時の native adapter に PeerConnection / raw RTCVideoFrame source / DataChannel / offer / answer / ICE の実装骨格がある。

## ビルド

```bash
cd sender-mac
swift build
```

libwebrtc native framework の検出:

```bash
./Scripts/check-webrtc.sh
```

期待する配置:

```text
sender-mac/ThirdParty/WebRTC/WebRTC.xcframework
```

詳細は [../docs/sender-mac-webrtc.md](../docs/sender-mac-webrtc.md) を参照してください。

## カメラと format の確認

```bash
swift run sender-mac --list-devices
```

macOS のカメラ権限が必要です。拒否された場合は System Settings > Privacy & Security > Camera で Terminal など実行元を許可してください。

## HEVC/H.265 encode 検証

X5 を USB Webcam Mode で接続してから実行します。

```bash
swift run sender-mac \
  --device-name "Insta360 X5" \
  --width 2880 \
  --height 1440 \
  --fps 30 \
  --codec hevc \
  --bitrate 18000000 \
  --duration 10
```

H.264 fallback:

```bash
swift run sender-mac \
  --codec h264 \
  --bitrate 16000000 \
  --duration 10
```

本番 signaling-worker へ接続する場合:

```bash
swift run sender-mac \
  --signaling-url wss://x5-webrtc-signaling.lord-sasapple.workers.dev \
  --room x5-test-room \
  --duration 10
```

receiver が同じ room に入ると `peer-joined` を受けます。現時点では native libwebrtc が未リンクのため、offer 作成と media 送信は stub が警告ログを出します。

## WebRTC 送信経路

libwebrtc native は通常 raw frame を `RTCVideoSource` に渡し、libwebrtc 内部の encoder が RTP 化します。そのため sender-mac は raw `CVPixelBuffer` を WebRTC adapter へ渡します。

外部 `VTCompressionSession` は HEVC/H.265 と H.264 の hardware encode 可否、encode 時間、keyframe、encoded size を測るために残しています。実際の WebRTC 送信 codec は libwebrtc 側の codec negotiation と encoder 実装に依存します。HEVC/H.265 first を維持しつつ、H.264 fallback を必ず残します。

## 現在の制限

- `WebRTC.xcframework` は repo に同梱していません。
- `HAS_WEBRTC` 有効時の native adapter は実装骨格です。実際の framework API と照合して仕上げる必要があります。
- `WebRTC.xcframework` 未配置時は stub adapter で動きます。
- Xcode `.app` bundle と `Info.plist` は未作成です。
- WebRTC stats は未実装です。

## DataChannel timestamp 予定

`HAS_WEBRTC` 有効時は DataChannel `latency` へ送る実装骨格があります。未配置時は stub ログとして出します。

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
