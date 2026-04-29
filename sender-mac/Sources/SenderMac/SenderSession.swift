import Foundation

final class SenderSession: @unchecked Sendable {
    private let config: AppConfig
    private let webRTC: WebRTCSenderAdapter
    private let signalingClient: SignalingClient?

    init(config: AppConfig) {
        self.config = config

        if let signalingBaseURL = config.signalingBaseURL,
           let roomId = config.roomId,
           !roomId.isEmpty {
            signalingClient = SignalingClient(baseURL: signalingBaseURL, roomId: roomId)
        } else {
            signalingClient = nil
            if config.signalingBaseURL != nil || config.roomId != nil {
                Logger.warn("--signaling-url と --room はセットで指定してください。signaling 接続はスキップします")
            }
        }

        self.webRTC = WebRTCAdapterFactory.make(config: config, signalingClient: signalingClient)
    }

    func start() {
        webRTC.start()
        signalingClient?.onMessage = { [weak self] message in
            self?.handleSignalingMessage(message)
        }
        signalingClient?.connect()
    }

    func stop() {
        signalingClient?.disconnect()
        webRTC.stop()
    }

    func handleRawFrame(_ frame: RawVideoFrame) {
        webRTC.sendRawFrame(frame)
    }

    func handleEncodedFrame(_ frame: EncodedVideoFrame) {
        webRTC.sendEncodedFrame(frame)

        let sendTimeMs = Clock.wallTimeMs()
        let timestamp = FrameTimestampMessage(
            sequence: frame.log.sequence,
            captureTimeMs: frame.log.captureTimeMs,
            encodeStartTimeMs: frame.log.encodeStartTimeMs,
            encodeEndTimeMs: frame.log.encodeEndTimeMs,
            sendTimeMs: sendTimeMs
        )
        webRTC.sendFrameTimestamp(timestamp)
    }

    private func handleSignalingMessage(_ message: SignalingServerMessage) {
        switch message {
        case .joined(let roomId, let role):
            Logger.info("signaling joined: room=\(roomId) role=\(role.rawValue)")
        case .peerJoined(let role):
            Logger.info("signaling peer-joined: role=\(role.rawValue)")
            webRTC.handlePeerJoined(role: role)
        case .answer(let sdp):
            Logger.info("signaling answer を受信しました: sdpBytes=\(sdp.utf8.count)")
            webRTC.handleAnswer(sdp: sdp)
        case .iceCandidate(let candidate):
            Logger.info("signaling ICE candidate を受信しました: candidateBytes=\(candidate.candidate.utf8.count)")
            webRTC.handleRemoteIceCandidate(candidate)
        case .peerLeft(let role):
            Logger.info("signaling peer-left: role=\(role.rawValue)")
            webRTC.handlePeerLeft(role: role)
        case .pong:
            Logger.info("signaling pong を受信しました")
        case .error(let message):
            Logger.warn("signaling error: \(message)")
        case .latencyEcho(let sequence, let senderTimeMs, let receiverTimeMs):
            Logger.info("signaling latency-echo: seq=\(sequence) senderTimeMs=\(senderTimeMs) receiverTimeMs=\(receiverTimeMs)")
        case .offer:
            Logger.warn("sender が offer を受信しました。role 不一致の可能性があります")
        case .latencySync(let sequence, let senderTimeMs):
            Logger.info("signaling latency-sync を受信しました: seq=\(sequence) senderTimeMs=\(senderTimeMs)")
        case .unknown(let type):
            Logger.warn("未知の signaling message です: type=\(type)")
        }
    }
}
