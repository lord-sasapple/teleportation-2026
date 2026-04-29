# Latency Measurement

遅延測定は 3 層で行います。Layer 1 と Layer 2 はアプリ内で常時観測し、最終的な正確な値は Layer 3 の glass-to-glass 測定で決めます。

## Layer 1: WebRTC stats

sender / receiver で getStats 相当の統計を表示・ログ化します。P2P 経路、帯域、jitter、decode/render の詰まりを切り分けるための層です。

見る値:

- `selectedCandidatePair`
- `localCandidateType`
- `remoteCandidateType`
- `currentRoundTripTime`
- `availableOutgoingBitrate`
- `jitter`
- `jitterBufferDelay`
- `jitterBufferTargetDelay`
- `packetsLost`
- `framesSent`
- `framesReceived`
- `framesDecoded`
- `framesDropped`
- `frameWidth`
- `frameHeight`
- `framesPerSecond`
- `codec`

candidate type の意味:

- `host`: ローカルネットワーク上の直接候補です。LAN 内では最も低遅延になりやすい候補です。
- `srflx`: STUN で得た server reflexive 候補です。NAT 越えで使います。
- `prflx`: peer reflexive 候補です。接続チェック中に発見されることがあります。
- `relay`: TURN relay 候補です。メディアが TURN 経由になり、遅延が増えやすくなります。

`relay` になった場合は P2P 直接経路ではなく TURN を経由しています。この signaling-worker は TURN の代替ではないため、必要なら別途 TURN サービスを用意します。

## Layer 2: Application timestamp latency

sender 側で各フレームに近いタイミングで timestamp を作り、WebRTC DataChannel で receiver へ送ります。

sender -> receiver:

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

receiver は受信、デコード、描画のタイミングを overlay 表示・ログ化します。

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

Application timestamp は sender と receiver の時計同期ずれを含みます。NTP や monotonic clock の扱いを揃えても完全には一致しないため、この値は参考値として扱います。

## Layer 3: Glass-to-glass latency

最終的な実測値は glass-to-glass latency で確認します。

測定手順:

1. ミリ秒表示の LED タイマー、または高精度ストップウォッチを用意する。
2. X5 がそのタイマーを撮影するように置く。
3. sender-mac から Quest 3 へ WebRTC P2P 送信する。
4. Quest 3 内の 360 度表示にタイマーが映る状態にする。
5. 別カメラで、元のタイマー表示と Quest 3 内に表示されたタイマーを同時に撮影する。
6. 撮影動画をフレーム単位で確認し、元のタイマー表示と Quest 表示の差分を読む。
7. 複数回測り、中央値、p90、最大値を記録する。

この方法はカメラ、エンコード、ネットワーク、デコード、Unity texture 更新、OpenXR render submit、HMD 表示までを含むため、ユーザーが体感する遅延に最も近い値になります。

## 記録する条件

- roomId
- network 条件
- selected candidate pair と candidate type
- codec
- bitrate
- resolution
- fps
- encoder name
- decoder name
- Quest 3 thermal 状態
- H.265/H.264 の比較結果

