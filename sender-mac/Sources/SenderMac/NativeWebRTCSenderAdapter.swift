#if HAS_WEBRTC
import Foundation
import WebRTC

final class NativeWebRTCSenderAdapter: WebRTCSenderAdapter, @unchecked Sendable {
    private let config: AppConfig
    private weak var signalingClient: SignalingClient?
    private var hasLoggedEncodedFrame = false

    init(config: AppConfig, signalingClient: SignalingClient?) {
        self.config = config
        self.signalingClient = signalingClient
    }

    func start() {
        Logger.info("libwebrtc native framework を検出しました")
        Logger.warn("PeerConnection 実体は次ステップで有効化します。現在は native link probe と signaling bridge だけを確認します")
    }

    func stop() {
        Logger.info("Native WebRTC adapter を停止しました")
    }

    func handlePeerJoined(role: SignalingRole) {
        Logger.info("WebRTC native adapter が peer-joined を受信しました: role=\(role.rawValue)")
        Logger.warn("次ステップで RTCPeerConnectionFactory / offer 作成 / codec preference をここに実装します")
    }

    func handleAnswer(sdp: String) {
        Logger.info("WebRTC native adapter が answer を受信しました: sdpBytes=\(sdp.utf8.count)")
    }

    func handleRemoteIceCandidate(_ candidate: IceCandidatePayload) {
        Logger.info("WebRTC native adapter が ICE candidate を受信しました: candidateBytes=\(candidate.candidate.utf8.count)")
    }

    func handlePeerLeft(role: SignalingRole) {
        Logger.info("WebRTC native adapter が peer-left を受信しました: role=\(role.rawValue)")
    }

    func sendEncodedFrame(_ frame: EncodedVideoFrame) {
        if !hasLoggedEncodedFrame {
            hasLoggedEncodedFrame = true
            Logger.warn("encoded CMSampleBuffer -> libwebrtc video source bridge は次ステップで実装します")
        }

        if frame.log.sequence == 1 || frame.log.sequence % Int64(max(config.logEveryFrames, 1)) == 0 {
            Logger.info("native WebRTC frame bridge pending: seq=\(frame.log.sequence) bytes=\(frame.log.sizeBytes) codec=\(frame.log.codec.displayName)")
        }
    }

    func sendFrameTimestamp(_ message: FrameTimestampMessage) {
        guard message.sequence == 1 || message.sequence % Int64(max(config.logEveryFrames, 1)) == 0 else {
            return
        }

        if let json = message.jsonString() {
            Logger.info("native DataChannel send pending: \(json)")
        }
    }
}
#endif

