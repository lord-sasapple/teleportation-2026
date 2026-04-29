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

- X5 device discovery
- AVFoundation capture
- 2880x1440 / 30fps format selection
- CVPixelBuffer timestamping
- VideoToolbox HEVC/H.265 hardware encode
- H.264 fallback
- encode/capture/send timing log

## 3. receiver-quest decode/render 設計

Quest 3 側を設計します。

- Unity project
- OpenXR
- Android libwebrtc
- MediaCodec HEVC/H.265 hardware decode
- decoder name logging
- software decoder warning
- equirectangular texture to inside-out sphere

## 4. 遅延 overlay

sender/receiver の stats と timestamp を overlay とログに出します。

- WebRTC stats polling
- DataChannel `frame-timestamp`
- receiver の `frame-latency-report`
- estimated app latency
- selected candidate pair
- codec
- frames dropped

## 5. H.265 実機検証

HEVC/H.265 で WebRTC P2P が成立するか実機で検証します。

- SDP codec negotiation
- VideoToolbox encoder 設定
- MediaCodec decoder 選択
- Quest 3 で hardware decode になっているか
- 12Mbps から 25Mbps の bitrate sweep

## 6. H.264 比較

H.264 fallback で同じ構成を動かし、HEVC/H.265 と比較します。

- 同じ解像度と fps
- 同じネットワーク条件
- WebRTC stats
- Application timestamp
- Glass-to-glass latency

