# X5 Quest WebRTC Telepresence MVP

Insta360 X5, MacBook M3, HEVC/H.265, WebRTC 1:1 P2P, and Quest 3 を使う低遅延 360 度テレプレゼンス MVP です。

現在の実装では、Cloudflare Workers + Durable Objects の signaling-worker、共有プロトコル、sender-mac の capture/encode/WebRTC 送信骨格、receiver-quest の Unity/signaling/overlay/rendering skeleton、Mac だけで実験するための receiver-mac を用意しています。映像と音声は signaling-worker を通りません。

## 構成

```text
docs/
shared/protocol/
signaling-worker/
sender-mac/
receiver-quest/
receiver-mac/
```

## MVP 方針

- WebRTC は 1:1 P2P です。
- Cloudflare Worker は SDP、ICE candidate、軽量な測定制御メッセージだけを交換します。
- SFU、RTMP、HLS、メディア中継は導入しません。
- コーデックは HEVC/H.265 first、H.264 fallback です。
- 遅延測定は WebRTC stats、Application timestamp、Glass-to-glass の 3 層で進めます。

## 最初に動かすもの

```bash
cd signaling-worker
npm install
npm run typecheck
npm run dev
```

別ターミナルで確認します。

```bash
curl http://127.0.0.1:8787/healthz
npm test
```

詳細は [signaling-worker/README.md](signaling-worker/README.md) を参照してください。

## sender-mac smoke

カメラなしで Cloudflare signaling へ接続確認できます。

```bash
cd sender-mac
WEBRTC_PROVIDER=livekit ./Scripts/run-signaling-only.sh
```

X5 接続後は device list と HEVC/H.264 比較を実行します。

```bash
WEBRTC_PROVIDER=livekit ./Scripts/run-sender-smoke.sh
WEBRTC_PROVIDER=livekit DURATION=60 ./Scripts/run-codec-comparison.sh
```

## Pion HEVC P2P bridge

LiveKitWebRTC で HEVC/H.265 送信 codec が見えない場合の検証経路として、sender-mac の VideoToolbox HEVC hardware encode 出力を localhost TCP で Go/Pion へ渡し、Pion から WebRTC H.265 P2P 送信します。`--pion-frame-socket` 指定時の sender-mac は Pion 専用モードになり、LiveKitWebRTC / signaling は起動しません。

```bash
cd tools/pion-hevc-sender
go run . --room pion-routeb-wan-001 --duration 600 --listen-frames 127.0.0.1:5005 --fps 30 --queue-size 3
```

```bash
cd sender-mac
WEBRTC_PROVIDER=livekit swift run sender-mac \
  --codec hevc \
  --width 1920 \
  --height 1080 \
  --fps 30 \
  --bitrate 6000000 \
  --duration 600 \
  --pion-frame-socket 127.0.0.1:5005
```

## receiver-quest

Unity 2022.3 LTS 以降で `receiver-quest` を開きます。現時点では Android native libwebrtc / MediaCodec 実装前の skeleton で、signaling、DataChannel timestamp 処理、stats overlay、inside-out sphere renderer まで入っています。

## receiver-mac

Quest が手元にない時の Mac-only 実験用 receiver です。MVP の本命は `receiver-quest` のままですが、sender の signaling、offer/answer、ICE、codec negotiation、低遅延ログを Mac 上で早く試すために置いています。

```bash
cd receiver-mac
WEBRTC_PROVIDER=livekit swift build
WEBRTC_PROVIDER=livekit ./Scripts/run-receiver-signaling.sh
```

内蔵カメラで sender と receiver を同じ Mac 上でまとめて起動する場合:

```bash
./scripts/run-mac-builtin-camera-p2p.sh
```
