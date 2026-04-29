# receiver-mac

macOS 上で低遅延 WebRTC 受信を行う実験用ネイティブ受信アプリです。Quest が無い環境でも sender の検証を継続できることを目的にしています。本命の受信側は `receiver-quest` です。

## 目標

- WebRTC 1:1 P2P 受信
- HEVC/H.265 first、H.264 fallback
- 低遅延志向の設定で受信
- 360 度表示（マウス視点操作）は `Viewer360` に段階実装

## 現在の実装

- `WEBRTC_PROVIDER=livekit` で LiveKitWebRTC 依存を有効化
- signaling-worker との `join` / `offer` / `answer` / `ice-candidate` / `leave` を処理
- sender と同じ `--ice-server` 指定に対応
- 受信 WebRTC アダプタ境界
	- `LiveKitReceiverWebRTCAdapter`（livekit 有効時）
	- `NativeReceiverWebRTCAdapter`（fallback）
- 360 viewer の基礎 (`Viewer360`) を追加

## ビルド

```bash
cd receiver-mac
swift build
WEBRTC_PROVIDER=livekit swift build
```

## 実行

signaling-only（接続確認）:

```bash
cd receiver-mac
./Scripts/run-receiver-signaling.sh
```

sender-mac の内蔵カメラ送信も含めて Mac 1 台でまとめて試す:

```bash
cd ..
./scripts/run-mac-builtin-camera-p2p.sh
```

livekit 経路で受信開始（現時点は受信骨組み）:

```bash
cd receiver-mac
WEBRTC_PROVIDER=livekit swift run receiver-mac \
	--signaling-url ws://127.0.0.1:8787 \
	--room x5-test-room \
	--codec hevc \
	--ice-server stun:stun.l.google.com:19302 \
	--duration 30
```

`SIGNALING_ONLY=0 ./Scripts/run-receiver-signaling.sh` で viewer も起動します。

## 低遅延・高画質のための次段実装

1. `LiveKitReceiverWebRTCAdapter` に VideoTrack 受信コールバックを接続
2. 受信フレームを `CVPixelBuffer` として `Viewer360` に受け渡し
3. `Viewer360` を Metal/SceneKit 実表示へ拡張し、equirectangular sphere 表示を実装
4. `DesktopWebRTCClient` と `CWebRTCShim` を Objective-C++ bridge に差し替え、VideoToolbox 指標を露出

この段階で、Quest を使わずに macOS だけで受信品質・低遅延挙動の検証が継続できます。ただし、このアプリを SFU や media relay の代替にしません。media path は sender-mac と receiver-mac の 1:1 P2P です。
