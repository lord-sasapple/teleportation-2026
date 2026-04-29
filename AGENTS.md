# AGENTS.md

このリポジトリは 3 つのアプリからなる低遅延 360 度テレプレゼンス MVP です。

- `sender-mac`: MacBook M3 上の Swift/macOS 送信アプリです。
- `signaling-worker`: Cloudflare Workers + Durable Objects のシグナリング専用サーバーです。
- `receiver-quest`: Quest 3 上の Unity 受信アプリです。

## 重要な制約

- `signaling-worker` はメディアを扱ってはいけません。
- SFU、RTMP、HLS を導入しないでください。
- WebRTC は 1:1 P2P を前提にしてください。
- まず HEVC/H.265/P2P/1:1 を優先してください。
- H.264 fallback は必ず残してください。
- 遅延測定の仕組みを軽視しないでください。
- TURN サーバーをこのリポジトリの signaling-worker として実装しないでください。

## 依存関係とビルド

- 依存関係は各ディレクトリ内に閉じてください。
- ルートで Swift、Unity、Node を無理に一括ビルドしないでください。
- TypeScript は `signaling-worker` で `npm run typecheck` を通してください。

## ドキュメント

変更したら README と `docs/` も更新してください。特にコーデック方針、シグナリング仕様、遅延測定仕様は実装とずれないようにしてください。

