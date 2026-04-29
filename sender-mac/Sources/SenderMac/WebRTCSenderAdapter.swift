import CoreMedia
import Foundation

struct EncodedVideoFrame: @unchecked Sendable {
    let sampleBuffer: CMSampleBuffer
    let log: EncodedFrameLog
}

protocol WebRTCSenderAdapter: Sendable {
    func start()
    func stop()
    func handlePeerJoined(role: SignalingRole)
    func handleAnswer(sdp: String)
    func handleRemoteIceCandidate(_ candidate: IceCandidatePayload)
    func handlePeerLeft(role: SignalingRole)
    func sendEncodedFrame(_ frame: EncodedVideoFrame)
    func sendFrameTimestamp(_ message: FrameTimestampMessage)
}

final class NativeWebRTCSenderUnavailableAdapter: WebRTCSenderAdapter, @unchecked Sendable {
    private let config: AppConfig
    private var hasLoggedFrameBridge = false

    init(config: AppConfig) {
        self.config = config
    }

    func start() {
        Logger.warn("libwebrtc native はまだリンクされていません。capture/encode と signaling のみ実行します")
    }

    func stop() {
        Logger.info("WebRTC adapter stub を停止しました")
    }

    func handlePeerJoined(role: SignalingRole) {
        Logger.warn("peer-joined を受信しましたが、native WebRTC 未接続のため offer は作成しません: role=\(role.rawValue)")
    }

    func handleAnswer(sdp: String) {
        Logger.warn("answer を受信しましたが、native WebRTC 未接続のため remote description は設定しません: sdpBytes=\(sdp.utf8.count)")
    }

    func handleRemoteIceCandidate(_ candidate: IceCandidatePayload) {
        Logger.warn("ICE candidate を受信しましたが、native WebRTC 未接続のため追加しません: candidateBytes=\(candidate.candidate.utf8.count)")
    }

    func handlePeerLeft(role: SignalingRole) {
        Logger.info("peer-left を WebRTC adapter stub で受信しました: role=\(role.rawValue)")
    }

    func sendEncodedFrame(_ frame: EncodedVideoFrame) {
        if !hasLoggedFrameBridge {
            hasLoggedFrameBridge = true
            Logger.warn("encoded frame bridge は stub です。次タスクで CMSampleBuffer を libwebrtc video source へ接続します")
        }

        if frame.log.sequence == 1 || frame.log.sequence % Int64(max(config.logEveryFrames, 1)) == 0 {
            Logger.info("WebRTC frame bridge stub: seq=\(frame.log.sequence) bytes=\(frame.log.sizeBytes) codec=\(frame.log.codec.displayName)")
        }
    }

    func sendFrameTimestamp(_ message: FrameTimestampMessage) {
        guard message.sequence == 1 || message.sequence % Int64(max(config.logEveryFrames, 1)) == 0 else {
            return
        }

        if let json = message.jsonString() {
            Logger.info("DataChannel timestamp stub: \(json)")
        }
    }
}
