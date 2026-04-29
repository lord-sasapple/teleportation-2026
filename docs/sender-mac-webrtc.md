# sender-mac WebRTC Native Integration

sender-mac は libwebrtc native を後から差し込める構成にしています。現時点では `WebRTC.xcframework` を repo に同梱せず、framework が存在する場合だけ SwiftPM が binary target と `HAS_WEBRTC` define を有効にします。

## 期待する配置

```text
sender-mac/ThirdParty/WebRTC/WebRTC.xcframework
```

確認:

```bash
cd sender-mac
./Scripts/check-webrtc.sh
swift package describe --type json
swift build
```

`WebRTC.xcframework` が存在しない場合、sender は明示的な stub adapter でビルドされます。capture、VideoToolbox encode、signaling、timestamp JSON までは動きます。

## Native adapter の境界

`WebRTCSenderAdapter` が sender の WebRTC 境界です。

- `handlePeerJoined`: receiver join 後に offer 作成へ進む
- `handleAnswer`: remote SDP answer を適用する
- `handleRemoteIceCandidate`: remote ICE candidate を追加する
- `sendRawFrame`: raw `CVPixelBuffer` を WebRTC video source へ渡す
- `sendEncodedFrame`: 外部 VideoToolbox encode の計測ログを受ける
- `sendFrameTimestamp`: DataChannel で `frame-timestamp` を送る

`HAS_WEBRTC` が有効な場合は `NativeWebRTCSenderAdapter` が選ばれます。未配置時は `NativeWebRTCSenderUnavailableAdapter` が選ばれ、未実装箇所をログで明示します。

## 次の実装順

1. macOS 対応の `WebRTC.xcframework` を用意する。
2. 現在の native adapter skeleton を選定した WebRTC build の API と照合する。
3. `RTCPeerConnectionFactory` を作成する。
4. sender 用 `RTCPeerConnection` を作成する。
5. raw `CVPixelBuffer` を `RTCVideoSource` へ渡す。
6. `RTCDataChannel` を作成し、`frame-timestamp` を送信する。
7. receiver の `peer-joined` で offer を作成する。
8. local SDP と local ICE を signaling-worker へ送る。
9. answer と remote ICE を受けて PeerConnection に適用する。
10. HEVC/H.265 first、H.264 fallback の codec preference を設定する。
11. 実際に選ばれた codec を stats に出す。

## Raw frame と VideoToolbox encode の扱い

libwebrtc native は通常 raw frame を `RTCVideoSource` に受け取り、内部 encoder が RTP packetization まで担当します。sender-mac の WebRTC 送信経路も raw `CVPixelBuffer` を渡す形に寄せています。

外部 `VTCompressionSession` は、MacBook M3 の HEVC/H.265 hardware encode 可否、encode latency、keyframe、encoded size を検証するための計測経路です。最終的な WebRTC RTP 送信では、選定した libwebrtc build の VideoToolbox encoder 経路を使います。どうしても外部 encoded bitstream を直接入れる必要が出た場合は、custom encoder / encoded image path を別途検証します。

## HEVC/H.265 注意

WebRTC の HEVC/H.265 対応は distribution と build flags に左右されます。HEVC negotiation が詰まった場合も、設計上は HEVC first を維持し、H.264 fallback で MVP を成立させます。現在は SDP の video payload 順を `H265` / `HEVC` / `H264` の順へ寄せる helper を用意しています。
