# receiver-quest Design Notes

`receiver-quest` は Quest 3 上の Unity app です。映像は WebRTC 1:1 P2P で sender-mac から直接受け、signaling-worker は SDP / ICE candidate / latency control JSON だけを中継します。SFU、RTMP、HLS、media relay は使いません。

## Current Skeleton

- `ReceiverQuestApp` が signaling、WebRTC client、latency overlay、inside-out sphere を束ねます。
- `SignalingClient` は `/room/:roomId?role=receiver` へ WebSocket 接続します。
- `AndroidQuestWebRTCClient` は Android native plugin への境界です。
- `EditorStubQuestWebRTCClient` は Unity Editor で placeholder texture と stub answer を返します。
- `InsideOutSphereRenderer` は equirectangular texture を内向き sphere に貼ります。
- `LatencyOverlay` は codec、decoder、candidate type、RTT、jitter、frame count、estimated app latency を表示します。

## Native Android Path

後続実装では `Assets/Plugins/Android/WebRTCBridge.java` を実 libwebrtc / MediaCodec 経路へ置き換えます。

1. libwebrtc Android PeerConnectionFactory を初期化する。
2. HEVC/H.265 を最優先に codec preference を設定する。
3. HEVC が成立しない場合は H.264 fallback へ落とす。
4. selected codec と SDP codec lines をログへ出す。
5. MediaCodec decoder 名を取得して overlay に渡す。
6. software decoder と判定した場合は警告を出す。
7. 受信映像を SurfaceTexture / external texture として Unity へ渡す。
8. DataChannel `frame-timestamp` を受けて `frame-latency-report` を生成する。

## Receiver Smoke Flow

1. Quest receiver が room に receiver role で join する。
2. sender-mac が同じ room に sender role で join する。
3. sender-mac が offer を作って signaling 経由で receiver へ送る。
4. receiver が remote offer を設定し answer を返す。
5. ICE candidate は双方向に signaling 経由で交換する。
6. WebRTC 接続後、media と DataChannel は P2P で直接流れる。

## Stats

overlay とログに出す値:

- selectedCandidatePair
- localCandidateType / remoteCandidateType
- currentRoundTripTimeMs
- jitterMs
- jitterBufferDelayMs
- jitterBufferTargetDelayMs
- packetsLost
- framesReceived / framesDecoded / framesDropped
- frameWidth / frameHeight / framesPerSecond
- codec
- decoderName
- softwareDecoder

## Latency

Application timestamp は DataChannel の `frame-timestamp` を起点に `frame-latency-report` を作ります。ただし sender と receiver の時計は完全同期していないため参考値です。最終的な遅延評価は `docs/latency-measurement.md` の glass-to-glass 測定を採用します。
