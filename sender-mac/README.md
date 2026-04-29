# sender-mac

MacBook M3 上で X5 の UVC 映像を取得し、VideoToolbox で HEVC/H.265 または H.264 に低遅延エンコードする sender 側の土台です。

SwiftPM 実行ファイル + Info.plist として実装しており、macOS app bundle 化は後続タスクです。

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
- `WEBRTC_PROVIDER=livekit` で LiveKitWebRTC の prebuilt libwebrtc XCFramework を使う。
- LiveKitWebRTC provider では PeerConnection / raw RTCVideoFrame source / DataChannel / offer / answer / ICE を実装している。
- encode 統計を収集・追跡する (SenderStatsMonitor)。
- codec negotiation を詳細にログする (CodecStatsLogger)。
- `--latency-report-test` で DataChannel 経由の latency report を集計する。
- `Info.plist` draft に Camera / Microphone / LocalNetwork 権限宣言を置いている。

## ビルド

```bash
cd sender-mac
swift build
```

libwebrtc native framework の検出:

```bash
./Scripts/check-webrtc.sh
```

LiveKitWebRTC provider を使う場合:

```bash
WEBRTC_PROVIDER=livekit ./Scripts/check-webrtc.sh
WEBRTC_PROVIDER=livekit swift build
```

期待する配置:

```text
sender-mac/ThirdParty/WebRTC/WebRTC.xcframework
```

詳細は [../docs/sender-mac-webrtc.md](../docs/sender-mac-webrtc.md) を参照してください。

## 内蔵カメラでテスト（X5 がない場合）

X5 がない MacBook で HEVC/H.265 と H.264 をテストできます:

```bash
# 内蔵カメラで HEVC encode テスト（10秒）
./Scripts/run-builtin-camera.sh

# H.264 で実行
CODEC=h264 ./Scripts/run-builtin-camera.sh

# 1 分間実行
DURATION=60 ./Scripts/run-builtin-camera.sh

# 直接実行
swift run sender-mac \
  --builtin-camera \
  --codec hevc \
  --bitrate 18000000 \
  --duration 10
```

内蔵カメラを使う場合の注意:

- 解像度は内蔵カメラのサポート仕様に依存します（通常は FHD or less）。
- `--width 2880 --height 1440` が実装されない場合は自動的に次点の format が選ばれます。
- Encode 統計（SenderStatsMonitor）は内蔵カメラでも有効です。

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

Application latency report 集計 (受信側が latency report を DataChannel で送る場合):

```bash
WEBRTC_PROVIDER=livekit swift run sender-mac \
  --latency-report-test \
  --signaling-url wss://x5-webrtc-signaling.lord-sasapple.workers.dev \
  --room latency-test-room \
  --duration 30
```

出力例:

```
===== application latency report 最終統計 =====
frame timestamps sent: 900
latency reports received: 895
estimated app latency (ms):
  平均: 45ms
  中央値: 44ms
  最小: 38ms
  最大: 62ms
  P95: 52ms
  P99: 58ms
capture-to-render latency (ms): 平均 48ms
テスト実行時間: 30000ms
=====================================
```

この値は sender/receiver の時計同期ズレを含む参考値です。正確な glass-to-glass latency は [../docs/latency-measurement.md](../docs/latency-measurement.md) の外部カメラ測定で確認します。`--glass-to-glass-test` は互換 alias として残しています。

カメラを使わず signaling と WebRTC 初期化だけを確認する場合:

```bash
WEBRTC_PROVIDER=livekit swift run sender-mac \
  --signaling-only \
  --signaling-url wss://x5-webrtc-signaling.lord-sasapple.workers.dev \
  --room x5-sender-signaling-smoke \
  --duration 5
```

または:

```bash
WEBRTC_PROVIDER=livekit ./Scripts/run-signaling-only.sh
```

receiver が同じ room に入ると `peer-joined` を受け、LiveKitWebRTC provider では offer 作成に進みます。local `WebRTC.xcframework` も `WEBRTC_PROVIDER=livekit` も使わない場合は stub adapter で動き、offer 作成と media 送信は警告ログだけになります。

## WebRTC 送信経路

libwebrtc native は通常 raw frame を `RTCVideoSource` に渡し、libwebrtc 内部の encoder が RTP 化します。そのため sender-mac は raw `CVPixelBuffer` を WebRTC adapter へ渡します。

外部 `VTCompressionSession` は HEVC/H.265 と H.264 の hardware encode 可否、encode 時間、keyframe、encoded size を測るために残しています。実際の WebRTC 送信 codec は libwebrtc 側の codec negotiation と encoder 実装に依存します。HEVC/H.265 first を維持しつつ、H.264 fallback を必ず残します。

`WEBRTC_PROVIDER=livekit` では LiveKit の `webrtc-xcframework` を prebuilt libwebrtc として使います。LiveKit の SFU や Cloud は使いません。media path は WebRTC 1:1 P2P のままです。

## 現在の制限

- local `WebRTC.xcframework` は repo に同梱していません。
- `WEBRTC_PROVIDER=livekit` の native adapter は compile 済みですが、X5 と Quest 3 receiver での実機 P2P 検証はまだです。
- `WebRTC.xcframework` 未配置時は stub adapter で動きます。
- Xcode `.app` bundle 化はまだです（SwiftPM 実行ファイルで十分です）。

## Statistics と Logging

### SenderStatsMonitor

Encode 統計を自動追跡します。30 フレームごと（`--log-every` で設定可能）に以下をログ出力：

```
encode stats: codec=HEVC/H.265 frames=900 avg-encode=5.23ms min=4.12ms max=8.45ms avg-size=245.0KB keyframe=5.0% capture-to-encode-stddev=0.82ms
```

終了時に最終統計を表示：

```
===== sender-mac 最終統計 =====
codec: HEVC/H.265
frames captured: 900
frames encoded: 900
frames sent: 900
encode avg: 5.23ms (min: 4.12ms, max: 8.45ms)
capture-to-encode stddev: 0.82ms
avg encoded size: 245 KB
total encoded: 220.50 MB
keyframe ratio: 5.0%
=================================
```

### CodecStatsLogger

Codec negotiation を詳細に記録：

```
サポートされているコーデック: H265, H264
offer SDP を作成しました: コーデック行数=3
  a=rtpmap:96 H265/90000
  a=rtpmap:97 H264/90000
コーデック優先度の設定:
  希望: H265, HEVC, H264
  ペイロード: {96: "H265", 97: "H264"}
answer SDP を受信しました: コーデック行数=2
===== コーデック交渉完了 =====
選択されたコーデック: H265
交渉時間: 145ms
============================
```

## DataChannel frame-timestamp

`WEBRTC_PROVIDER=livekit` 有効時に DataChannel `latency` へ送信：

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

Receiver が `frame-latency-report` を返すと、`--latency-report-test` mode で集計されます。

## 後続 TODO

詳細は [TODO.md](TODO.md) を参照してください：

- [ ] run sender with X5 using WEBRTC_PROVIDER=livekit
- [ ] verify HEVC/H.265 negotiation with Quest receiver
- [ ] DataChannel latency message end-to-end with receiver
- Xcode `.app` bundle 化（SwiftPM 実行ファイルで十分なため低優先）
