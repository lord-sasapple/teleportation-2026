# signaling-worker

Cloudflare Workers + Durable Objects による WebRTC 1:1 P2P 用のシグナリングサーバーです。

このサーバーは SDP、ICE candidate、遅延測定用の軽量 JSON 制御メッセージだけを交換します。映像、音声、RTP、RTCP、録画データは扱いません。メディア経路は MacBook M3 sender から Quest 3 receiver への WebRTC P2P です。

## 目的

- 1 room = 1 Durable Object として sender/receiver の 2 接続だけを管理する。
- sender から receiver へ `offer` を転送する。
- receiver から sender へ `answer` を転送する。
- 双方向の `ice-candidate` を転送する。
- 初期検証用に `latency-sync` / `latency-echo` を転送する。
- WebSocket Hibernation API を使い、Durable Object の復帰後も role を復元する。

## ローカル起動

```bash
npm install
npm run typecheck
npm run dev
```

ヘルスチェック:

```bash
curl http://127.0.0.1:8787/healthz
```

## Cloudflare へのデプロイ

```bash
npm install
npm run typecheck
npm run deploy
```

Durable Object binding は `ROOMS`、class name は `RoomObject` です。migration は SQLite Durable Objects 用の `new_sqlite_classes` を使います。

## 接続 URL

```text
ws://127.0.0.1:8787/room/x5-test-room?role=sender
ws://127.0.0.1:8787/room/x5-test-room?role=receiver
```

`role` は `sender` または `receiver` のみです。同じ room に同じ role は 1 接続だけ許可します。後から来た重複 role は `error` を送って閉じます。

## メッセージ仕様

client -> server:

```json
{ "type": "join", "roomId": "x5-test-room", "role": "sender" }
```

```json
{ "type": "offer", "sdp": "v=0..." }
```

```json
{ "type": "answer", "sdp": "v=0..." }
```

```json
{
  "type": "ice-candidate",
  "candidate": {
    "candidate": "candidate:...",
    "sdpMid": "0",
    "sdpMLineIndex": 0
  }
}
```

```json
{ "type": "leave" }
```

```json
{ "type": "ping" }
```

```json
{ "type": "latency-sync", "sequence": 1, "senderTimeMs": 1710000000000 }
```

```json
{
  "type": "latency-echo",
  "sequence": 1,
  "senderTimeMs": 1710000000000,
  "receiverTimeMs": 1710000000040
}
```

server -> client:

```json
{ "type": "joined", "roomId": "x5-test-room", "role": "sender" }
```

```json
{ "type": "peer-joined", "role": "receiver" }
```

```json
{ "type": "peer-left", "role": "receiver" }
```

```json
{ "type": "pong" }
```

```json
{ "type": "error", "message": "..." }
```

`offer`、`answer`、`ice-candidate`、`latency-sync`、`latency-echo` は相手へそのまま転送されます。SDP と candidate の全文は通常ログに出しません。

## sender/receiver の接続手順

1. sender が `/room/:roomId?role=sender` に WebSocket 接続する。
2. receiver が `/room/:roomId?role=receiver` に WebSocket 接続する。
3. 双方に `joined` が返る。
4. 片方がすでに接続済みなら、相手に `peer-joined` が送られる。
5. sender は `offer` を送る。
6. receiver は `answer` を返す。
7. 双方が `ice-candidate` を交換する。
8. WebRTC P2P 接続確立後、映像は P2P 経路で流れる。

MVP では保留キューを持ちません。相手が未接続の状態で `offer`、`answer`、`ice-candidate`、`latency-sync`、`latency-echo` を送ると `error` を返します。

## latency-sync / latency-echo

`latency-sync` と `latency-echo` は、初期検証用に signaling 経由で往復制御メッセージを確認するためのものです。

本命の Application timestamp latency は WebRTC DataChannel で `frame-timestamp` を sender から receiver に送り、receiver 側で `frame-latency-report` を overlay とログに出します。時計同期のずれがあるため、Application timestamp は参考値です。正確な glass-to-glass latency は外部カメラで測ります。

## STUN/TURN/SFU との違い

- STUN は P2P 可能な候補を見つけるための補助です。
- TURN は P2P が成立しない場合にメディアを relay する別サーバーです。
- SFU は複数参加者向けに RTP を受けて転送するメディアサーバーです。
- この Worker は signaling 専用で、STUN/TURN/SFU の代替ではありません。

TURN が必要になった場合でも、この signaling-worker では代替できません。別途 TURN サービスを用意し、WebRTC の ICE server 設定として sender/receiver に渡します。

## P2P と無料枠の注意

Cloudflare Workers/Durable Objects はシグナリングの軽量メッセージだけを扱う前提です。メディアを流さないため、無料枠での検証に向いています。ただし Durable Objects のリクエスト数、WebSocket 接続時間、ログ量には上限があります。長時間連続運用や多数 room の検証では Cloudflare の使用量を確認してください。

## 自動確認スクリプト

`npm run dev` を起動した状態で、別ターミナルから実行します。

```bash
npm test
```

このスクリプトは sender/receiver を接続し、`offer`、`answer`、双方向 `ice-candidate`、`latency-sync`、`latency-echo`、duplicate sender 拒否、`peer-left` を確認します。

