import Foundation

final class SenderSession: @unchecked Sendable {
    private let config: AppConfig
    private let webRTC: WebRTCSenderAdapter
    private let signalingClient: SignalingClient?
    private var statsMonitor: SenderStatsMonitor?
    private var didScheduleInitialOffer = false
    private let glassToGlassTestMode: GlassToGlassTestMode

    init(config: AppConfig) {
        self.config = config
        self.glassToGlassTestMode = GlassToGlassTestMode(enabled: config.glassToGlassTest)

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
        self.statsMonitor = SenderStatsMonitor(codec: config.codec, logEveryFrames: config.logEveryFrames)

        // 受信側が返す frame-latency-report を application latency 集計へ渡します。
        self.webRTC.setReceivedDataChannelHandler { [weak self] data in
            self?.handleReceivedDataChannelMessage(data)
        }
    }

    func setStatsMonitor(_ monitor: SenderStatsMonitor) {
        self.statsMonitor = monitor
    }

    func getGlassToGlassTestMode() -> GlassToGlassTestMode {
        glassToGlassTestMode
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
        statsMonitor?.recordSentFrame(frame.log.sequence)

        let sendTimeMs = Clock.wallTimeMs()
        let timestamp = FrameTimestampMessage(
            sequence: frame.log.sequence,
            captureTimeMs: frame.log.captureTimeMs,
            encodeStartTimeMs: frame.log.encodeStartTimeMs,
            encodeEndTimeMs: frame.log.encodeEndTimeMs,
            sendTimeMs: sendTimeMs
        )
        webRTC.sendFrameTimestamp(timestamp)
        glassToGlassTestMode.recordFrameTimestamp(timestamp)
    }

    private func handleSignalingMessage(_ message: SignalingServerMessage) {
        switch message {
        case .joined(let roomId, let role):
            Logger.info("signaling joined: room=\(roomId) role=\(role.rawValue)")
            if role == .sender && !didScheduleInitialOffer {
                didScheduleInitialOffer = true
                Logger.info("sender joined 後に offer 作成を一度だけ試みます")
                DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.webRTC.handlePeerJoined(role: .receiver)
                }
            }
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

    private func handleReceivedDataChannelMessage(_ data: Data) {
        guard let json = String(data: data, encoding: .utf8) else {
            return
        }

        if let jsonData = json.data(using: .utf8) {
            let decoder = JSONDecoder()
            do {
                if let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let type = jsonObject["type"] as? String,
                   type == "frame-latency-report" {
                    let report = try decoder.decode(FrameLatencyReportMessage.self, from: jsonData)
                    glassToGlassTestMode.recordLatencyReport(report)
                }
            } catch {
                Logger.info("DataChannel message を parse できません: \(error)")
            }
        }
    }
}
