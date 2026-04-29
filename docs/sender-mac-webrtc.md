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
- `sendEncodedFrame`: encoded `CMSampleBuffer` を WebRTC 送信経路へ渡す
- `sendFrameTimestamp`: DataChannel で `frame-timestamp` を送る

`HAS_WEBRTC` が有効な場合は `NativeWebRTCSenderAdapter` が選ばれます。未配置時は `NativeWebRTCSenderUnavailableAdapter` が選ばれ、未実装箇所をログで明示します。

## 次の実装順

1. macOS 対応の `WebRTC.xcframework` を用意する。
2. `RTCPeerConnectionFactory` を作成する。
3. sender 用 `RTCPeerConnection` を作成する。
4. `RTCDataChannel` を作成し、`frame-timestamp` を送信する。
5. receiver の `peer-joined` で offer を作成する。
6. local SDP と local ICE を signaling-worker へ送る。
7. answer と remote ICE を受けて PeerConnection に適用する。
8. HEVC/H.265 first、H.264 fallback の codec preference を設定する。
9. 実際に選ばれた codec を stats に出す。
10. encoded frame path を libwebrtc video source または encoder integration に接続する。

## HEVC/H.265 注意

WebRTC の HEVC/H.265 対応は distribution と build flags に左右されます。HEVC negotiation が詰まった場合も、設計上は HEVC first を維持し、H.264 fallback で MVP を成立させます。

