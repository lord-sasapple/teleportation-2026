# receiver-quest

Quest 3 上で動く Unity 受信アプリの初期 skeleton です。WebRTC media path は引き続き 1:1 P2P で、Cloudflare signaling-worker は SDP / ICE candidate / 軽量な遅延測定メッセージだけを扱います。

## 現在入っているもの

- Unity project skeleton (`Packages/`, `ProjectSettings/`)。
- OpenXR / XR Management package 依存関係。
- Cloudflare signaling-worker へ receiver role で接続する C# client。
- `offer` / `ice-candidate` / `latency-sync` / `peer-left` の受信処理。
- `answer` / `ice-candidate` / `latency-echo` / `leave` の送信処理。
- Android native bridge 境界 (`WebRTCBridge.java`, `AndroidQuestWebRTCClient`)。
- Editor stub receiver。Unity Editor では placeholder texture と stub answer を返します。
- DataChannel `frame-timestamp` receiver と `frame-latency-report` 生成。
- stats / decoder / latency overlay。
- equirectangular texture を貼る inside-out sphere renderer。
- 空 scene でも `ReceiverQuestApp` を自動生成する bootstrap。

## 実装方針

- libwebrtc Android で WebRTC 1:1 P2P 映像を受信します。
- MediaCodec HEVC/H.265 hardware decode を初手にします。
- H.264 fallback を必ず残します。
- 受信した equirectangular texture を inside-out sphere に貼ります。
- OpenXR で HMD 内に 360 度表示します。
- DataChannel で `frame-timestamp` を受け取ります。
- overlay に codec、decoder 名、candidate type、RTT、jitter、frames decoded/dropped、推定 latency を表示します。
- software decode fallback を検出したら警告します。

## 起動方法

Unity 2022.3 LTS 以降を想定しています。

1. Unity Hub で `receiver-quest` ディレクトリを開きます。
2. Android Build Support と OpenXR を有効にします。
3. Quest 3 を接続し、Android target で Build & Run します。
4. `ReceiverQuestApp` の `signalingUrl` と `roomId` を sender と合わせます。

現時点の Android `WebRTCBridge.java` は native libwebrtc / MediaCodec 実装前の stub です。Quest 実機で映像を出すには、後続タスクで Android libwebrtc と SurfaceTexture / external texture bridge を実装します。

## Receiver latency report

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

## 後続 TODO

詳細は [TODO.md](TODO.md) を参照してください。

## Unity Editor で受信側をテストする（Quest がない環境向け）

開発中は Quest 実機が無くても Unity Editor を使って受信側のシグナリング、DataChannel、overlay 表示などの動作確認ができます。プロジェクトには Editor 用の stub 実装 (`EditorStubQuestWebRTCClient`) が含まれており、placeholder テクスチャと stub の `answer` を返します。

手順:

1. signaling-worker をローカルで起動します（別ターミナル）:

```bash
cd signaling-worker
npm install
npm run dev

# 確認
curl http://127.0.0.1:8787/healthz
```

2. sender 側をローカルで起動します（内蔵カメラや signaling-only を使ってテスト可能）:

```bash
cd sender-mac
# 内蔵カメラで送信（Editor stub で latency/datachannel の確認）
./Scripts/run-builtin-camera.sh \
  # 必要に応じて CODEC=h264 などを指定

# または signaling-only モードで接続のみ確認
WEBRTC_PROVIDER=livekit ./Scripts/run-signaling-only.sh
```

3. Unity Editor で `receiver-quest` を開き、Play を押します。

4. `ReceiverQuestApp` の inspector 上で `signalingUrl` を `ws://127.0.0.1:8787`（またはローカルの wrangler dev URL）に、`roomId` を sender と合わせます。

5. Sender が `offer` を送ると Editor stub が `answer` を返し、overlay に接続状態・統計が表示されます。DataChannel 経由の `frame-timestamp` で latency overlay の挙動も確認できます。

注意点:
- Editor stub は実際のビデオストリームをデコードしないため、映像品質の検証はできません。映像の実再生を Mac だけで試す場合は `receiver-mac` を使います。
- HEVC を使う完全な Quest end-to-end テストを行うには Quest 実機が必要です。開発時は `receiver-mac` と `--codec h264` で互換性の高い経路を使うと速く検証できます。

次のステップ候補:
- Android native client の MediaCodec decode と SurfaceTexture / external texture bridge を実装する
- `receiver-mac` の VideoTrack -> CVPixelBuffer -> 360 viewer 表示を実装する
