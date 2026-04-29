# Implementation Plan

## 1. signaling-worker

Cloudflare Workers + Durable Objects の signaling-worker を最初に完成させます。

- TypeScript
- wrangler
- Durable Objects
- WebSocket Hibernation API
- `state.acceptWebSocket(server)`
- 1 room = 1 Durable Object
- sender/receiver の 2 接続だけを許可
- SDP / ICE candidate / latency control JSON だけを中継
- メディアは扱わない

## 2. sender-mac capture/encode 設計

次に MacBook M3 側を設計します。

- X5 device discovery: 初期実装済み
- AVFoundation capture: 初期実装済み
- 2880x1440 / 30fps format selection: 初期実装済み
- CVPixelBuffer timestamping: 初期実装済み
- VideoToolbox HEVC/H.265 hardware encode: 初期実装済み
- H.264 fallback: 初期実装済み
- encode/capture timing log: 初期実装済み
- WebRTC adapter boundary: 初期実装済み
- typed signaling server message handling: 初期実装済み
- DataChannel timestamp JSON generation: 初期実装済み
- optional `WebRTC.xcframework` SwiftPM wiring: 初期実装済み
- native WebRTC link-probe adapter skeleton: 初期実装済み
- raw CVPixelBuffer bridge to WebRTC adapter: 初期実装済み
- native PeerConnection / offer / answer / ICE skeleton: 初期実装済み
- native DataChannel timestamp send skeleton: 初期実装済み
- SDP HEVC/H.265 first payload ordering helper: 初期実装済み
- LiveKitWebRTC provider compile: 初期実装済み
- selected WebRTC.xcframework との API 照合: LiveKitWebRTC で初期実装済み
- DataChannel timestamp end-to-end: 次タスク

## 3. receiver-quest decode/render 設計

Quest 3 側を設計します。

- Unity project skeleton: 初期実装済み
- OpenXR package setup: 初期実装済み
- receiver role signaling client: 初期実装済み
- Android libwebrtc bridge boundary: 初期実装済み
- Editor stub receiver: 初期実装済み
- MediaCodec HEVC/H.265 hardware decode: native 実装は次タスク
- decoder name logging: overlay/API field は初期実装済み、native 実値取得は次タスク
- software decoder warning: overlay/API field は初期実装済み、native 判定は次タスク
- equirectangular texture to inside-out sphere: 初期実装済み

## 4. 遅延 overlay

sender/receiver の stats と timestamp を overlay とログに出します。

- receiver WebRTC stats polling interface: 初期実装済み
- sender DataChannel `frame-timestamp` send path: 初期実装済み
- receiver DataChannel `frame-timestamp` parse: 初期実装済み
- receiver の `frame-latency-report`: 初期実装済み
- estimated app latency overlay: 初期実装済み
- selected candidate pair overlay field: 初期実装済み
- codec / decoder overlay field: 初期実装済み
- frames dropped overlay field: 初期実装済み
- sender SenderStatsMonitor: 次タスク

## 5. H.265 実機検証

HEVC/H.265 で WebRTC P2P が成立するか実機で検証します。

- SDP codec negotiation logging helper: 初期実装済み
- sender-mac LiveKitWebRTC provider compile: 初期検証済み
- sender-mac signaling-only 起動確認: 実施
- VideoToolbox encoder 設定: 初期実装済み
- MediaCodec decoder 選択: native 実装は次タスク
- Quest 3 で hardware decode になっているか: 実機検証待ち
- 12Mbps から 25Mbps の bitrate sweep: 手順作成済み

## 6. H.264 比較

H.264 fallback で同じ構成を動かし、HEVC/H.265 と比較します。

- 同じ解像度と fps: `run-codec-comparison.sh` で固定
- 同じネットワーク条件: test plan に明記
- WebRTC stats: receiver overlay field と比較表を用意
- Application timestamp: sender/receiver 型と実装骨格を用意
- Glass-to-glass latency: 測定手順と比較表を用意
