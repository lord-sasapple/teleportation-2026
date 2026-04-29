# sender-mac WebRTC Native Integration

sender-mac は libwebrtc native を後から差し込める構成にしています。現時点では `WebRTC.xcframework` を repo に同梱せず、framework が存在する場合だけ SwiftPM が binary target と `HAS_WEBRTC` define を有効にします。

## 期待する配置

```text
sender-mac/ThirdParty/WebRTC/WebRTC.xcframework
```

もうひとつの候補として LiveKit の `webrtc-xcframework` を SwiftPM dependency として使えます。LiveKit distribution は `LiveKitWebRTC` module で、Objective-C symbols は `LKRTC*` に prefix されています。macOS arm64/x64 を含むため、MacBook M3 sender の候補として扱います。

確認:

```bash
cd sender-mac
./Scripts/check-webrtc.sh
swift package describe --type json
swift build
```

LiveKit provider を使う場合:

```bash
WEBRTC_PROVIDER=livekit ./Scripts/check-webrtc.sh
WEBRTC_PROVIDER=livekit swift build
```

この provider は compile 確認済みです。LiveKit の SFU/Cloud は使わず、`LiveKitWebRTC` を prebuilt libwebrtc binary として使います。

`WebRTC.xcframework` が存在しない場合、sender は明示的な stub adapter でビルドされます。capture、VideoToolbox encode、signaling、timestamp JSON までは動きます。

## Native adapter の境界

`WebRTCSenderAdapter` が sender の WebRTC 境界です。

- `handlePeerJoined`: receiver join 後に offer 作成へ進む
- `handleAnswer`: remote SDP answer を適用する
- `handleRemoteIceCandidate`: remote ICE candidate を追加する
- `sendRawFrame`: raw `CVPixelBuffer` を WebRTC video source へ渡す
- `sendEncodedFrame`: 外部 VideoToolbox encode の計測ログを受ける
- `sendFrameTimestamp`: DataChannel で `frame-timestamp` を送る

`HAS_WEBRTC` が有効な場合は `NativeWebRTCSenderAdapter` が選ばれます。`HAS_LIVEKIT_WEBRTC` が有効な場合は `LiveKitWebRTCSenderAdapter` が選ばれます。未配置時は `NativeWebRTCSenderUnavailableAdapter` が選ばれ、未実装箇所をログで明示します。

`LiveKitWebRTCSenderAdapter` は次を実装しています。

- `LKRTCPeerConnectionFactory`
- `LKRTCPeerConnection`
- `LKRTCVideoSource`
- `LKRTCVideoCapturer`
- raw `CVPixelBuffer` -> `LKRTCCVPixelBuffer` -> `LKRTCVideoFrame`
- `LKRTCDataChannel` label `latency`
- offer 作成と signaling-worker への送信
- answer 適用
- local/remote ICE candidate
- SDP payload ordering helper による HEVC/H.265 first の試行

## 次の実装順

1. X5 を接続し、`WEBRTC_PROVIDER=livekit swift run sender-mac --list-devices` で format を確認する。
2. receiver が signaling room に入った状態で sender を起動し、offer/answer/ICE を確認する。
3. DataChannel `latency` の open と `frame-timestamp` 到達を receiver 側で確認する。
4. HEVC/H.265 が SDP に出るか、実際に選ばれるか確認する。
5. H.264 fallback で同じ P2P flow を比較する。
6. 実際に選ばれた codec を stats に出す。

## Raw frame と VideoToolbox encode の扱い

libwebrtc native は通常 raw frame を `RTCVideoSource` に受け取り、内部 encoder が RTP packetization まで担当します。sender-mac の WebRTC 送信経路も raw `CVPixelBuffer` を渡す形に寄せています。

外部 `VTCompressionSession` は、MacBook M3 の HEVC/H.265 hardware encode 可否、encode latency、keyframe、encoded size を検証するための計測経路です。最終的な WebRTC RTP 送信では、選定した libwebrtc build の VideoToolbox encoder 経路を使います。どうしても外部 encoded bitstream を直接入れる必要が出た場合は、custom encoder / encoded image path を別途検証します。

## Pion HEVC bridge

LiveKitWebRTC / stasel WebRTC の macOS build で HEVC/H.265 送信 codec が公開されない場合の実機検証経路として、`--pion-frame-socket <host:port>` を指定できます。このモードでは sender-mac は capture と VideoToolbox encode だけを行い、HEVC Annex B access unit を length-prefixed TCP で Go/Pion へ送ります。LiveKitWebRTC PeerConnection と signaling-worker 接続は起動しません。

Go 側の `tools/pion-hevc-sender` は `--listen-frames` で TCP を受け、`--queue-size` の低遅延キューと `--fps` ticker で `WriteSample` をペーシングします。キューが詰まった場合は古い frame を捨て、最新 frame を優先します。ただし WAN 検証の既定では sender-mac の capture/encode fps と Go の send fps を同じ値にして、エンコード済み HEVC access unit の通常間引きを避けます。

## HEVC/H.265 注意

WebRTC の HEVC/H.265 対応は distribution と build flags に左右されます。HEVC negotiation が詰まった場合も、設計上は HEVC first を維持し、H.264 fallback で MVP を成立させます。現在は SDP の video payload 順を `H265` / `HEVC` / `H264` の順へ寄せる helper を用意しています。
