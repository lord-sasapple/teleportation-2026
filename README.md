# X5 Quest WebRTC Telepresence MVP

Insta360 X5, MacBook M3, HEVC/H.265, WebRTC 1:1 P2P, and Quest 3 を使う低遅延 360 度テレプレゼンス MVP です。

この初期実装では、Cloudflare Workers + Durable Objects の signaling-worker と、共有プロトコル、設計ドキュメント、sender/receiver の README/TODO を用意しています。映像と音声は signaling-worker を通りません。

## 構成

```text
docs/
shared/protocol/
signaling-worker/
sender-mac/
receiver-quest/
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

