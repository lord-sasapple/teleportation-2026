# Codec Plan

## Phase 1: HEVC/H.265 first

最初のターゲットは HEVC/H.265 です。

MacBook M3 側:

- WebRTC 送信経路では、選定した libwebrtc build の VideoToolbox HEVC hardware encode を使う前提です。
- LiveKitWebRTC などの macOS libwebrtc distribution で HEVC/H.265 送信 codec が公開されない場合は、検証経路として sender-mac の外部 VideoToolbox HEVC encode を Go/Pion に渡す Pion HEVC bridge を使います。
- sender-mac には外部 `VTCompressionSession` の計測経路も残し、HEVC/H.265 と H.264 の hardware encode 可否と encode latency を確認します。
- realtime encode を有効にします。
- frame reordering は off にします。
- B-frame なし相当の低遅延設定にします。
- keyframe interval は短めにします。
- 入力は 2880x1440 / 30fps / 2:1 equirectangular を想定します。
- bitrate は最初 12Mbps から 25Mbps の範囲で検証します。

Quest 3 側:

- MediaCodec HEVC hardware decode を使う前提です。
- 実際に選ばれた decoder 名を overlay とログに表示します。
- software decoder に落ちた場合は警告を出します。
- WebRTC stats overlay に実際の codec を表示します。

## Phase 2: H.264 fallback / comparison

HEVC/H.265 の WebRTC negotiation、packetization、MediaCodec decode 経路で詰まった場合に備えて H.264 fallback を残します。

H.264 fallback は次の用途でも使います。

- HEVC が成立しない環境で MVP を成立させる。
- HEVC と H.264 の latency、bitrate、画質を比較する。
- WebRTC P2P と Unity render 経路だけを先に検証する。

## Phase 3: AV1 は後回し

今回の MVP では AV1 は使いません。MacBook M3 では AV1 hardware encode が初手の本命ではないため、HEVC/H.265 と H.264 の実機検証後に再評価します。

## HEVC WebRTC negotiation の注意

WebRTC 実装によって HEVC/H.265 の扱いは難しい場合があります。SDP codec negotiation のログを必ず取れる設計にし、実際に選ばれた codec を stats overlay に表示します。

Pion HEVC bridge では sender-mac から届く HEVC Annex B frame を低遅延キューに入れ、`fps` ticker で送信します。HEVC は P/B frame が参照チェーンを持つため、エンコード後に送信側で frame を間引くと receiver decoder が固まりやすくなります。WAN 越し検証ではまず X5 公式 Webcam Mode の 2:1 出力である 2880x1440 / 30fps を維持し、`--fps` も 30 に揃えたまま、bitrate と keyframe interval で負荷を落とします。

HEVC で交渉やデコードに失敗した場合でも、設計、docs、型定義では HEVC first を維持します。そのうえで H.264 fallback で MVP を成立させ、TODO に HEVC 再検証項目を残します。
