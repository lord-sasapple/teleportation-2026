#if HAS_LIVEKIT_WEBRTC
import CoreVideo
import Foundation
@preconcurrency import LiveKitWebRTC

final class LiveKitWebRTCSenderAdapter: NSObject, WebRTCSenderAdapter, @unchecked Sendable {
    private let config: AppConfig
    private weak var signalingClient: SignalingClient?
    private let queue = DispatchQueue(label: "telepresence.sender.livekit-webrtc")
    private let factory: LKRTCPeerConnectionFactory
    private var peerConnection: LKRTCPeerConnection?
    private var videoSource: LKRTCVideoSource?
    private var videoCapturer: LKRTCVideoCapturer?
    private var dataChannel: LKRTCDataChannel?
    private var hasLoggedEncodedFrame = false

    init(config: AppConfig, signalingClient: SignalingClient?) {
        self.config = config
        self.signalingClient = signalingClient
        LKRTCInitializeSSL()

        let encoderFactory = LKRTCDefaultVideoEncoderFactory()
        let decoderFactory = LKRTCDefaultVideoDecoderFactory()
        Self.logSupportedCodecs(encoderFactory: encoderFactory)
        factory = LKRTCPeerConnectionFactory(encoderFactory: encoderFactory, decoderFactory: decoderFactory)

        super.init()
    }

    deinit {
        LKRTCCleanupSSL()
    }

    func start() {
        Logger.info("LiveKitWebRTC framework を検出しました。P2P PeerConnection を初期化します")
        queue.async { [weak self] in
            self?.ensurePeerConnection()
        }
    }

    func stop() {
        queue.sync {
            dataChannel?.close()
            dataChannel = nil
            peerConnection?.close()
            peerConnection = nil
            videoSource = nil
            videoCapturer = nil
        }
        Logger.info("LiveKitWebRTC adapter を停止しました")
    }

    func handlePeerJoined(role: SignalingRole) {
        guard role == .receiver else {
            Logger.warn("sender が receiver 以外の peer-joined を受信しました: role=\(role.rawValue)")
            return
        }

        queue.async { [weak self] in
            self?.createOffer()
        }
    }

    func handleAnswer(sdp: String) {
        queue.async { [weak self] in
            guard let peerConnection = self?.peerConnection else {
                Logger.warn("answer 受信時点で PeerConnection がありません")
                return
            }

            let description = LKRTCSessionDescription(type: .answer, sdp: sdp)
            peerConnection.setRemoteDescription(description) { error in
                if let error {
                    Logger.warn("remote answer 設定に失敗しました: \(error.localizedDescription)")
                } else {
                    Logger.info("remote answer を設定しました")
                }
            }
        }
    }

    func handleRemoteIceCandidate(_ candidate: IceCandidatePayload) {
        queue.async { [weak self] in
            guard let peerConnection = self?.peerConnection else {
                Logger.warn("ICE candidate 受信時点で PeerConnection がありません")
                return
            }

            let rtcCandidate = LKRTCIceCandidate(
                sdp: candidate.candidate,
                sdpMLineIndex: Int32(candidate.sdpMLineIndex ?? 0),
                sdpMid: candidate.sdpMid
            )

            peerConnection.add(rtcCandidate) { error in
                if let error {
                    Logger.warn("remote ICE candidate 追加に失敗しました: \(error.localizedDescription)")
                } else {
                    Logger.info("remote ICE candidate を追加しました: candidateBytes=\(candidate.candidate.utf8.count)")
                }
            }
        }
    }

    func handlePeerLeft(role: SignalingRole) {
        Logger.info("LiveKitWebRTC adapter が peer-left を受信しました: role=\(role.rawValue)")
    }

    func sendRawFrame(_ frame: RawVideoFrame) {
        queue.async { [weak self] in
            guard let self, let videoSource, let videoCapturer else {
                return
            }

            let buffer = LKRTCCVPixelBuffer(pixelBuffer: frame.pixelBuffer)
            let videoFrame = LKRTCVideoFrame(buffer: buffer, rotation: ._0, timeStampNs: frame.presentationTimeNs)
            videoSource.capturer(videoCapturer, didCapture: videoFrame)

            if frame.sequence == 1 || frame.sequence % Int64(max(self.config.logEveryFrames, 1)) == 0 {
                Logger.info("raw frame を LiveKitWebRTC video source へ渡しました: seq=\(frame.sequence) \(frame.width)x\(frame.height)")
            }
        }
    }

    func sendEncodedFrame(_ frame: EncodedVideoFrame) {
        if !hasLoggedEncodedFrame {
            hasLoggedEncodedFrame = true
            Logger.info("encoded CMSampleBuffer は VideoToolbox 計測用として保持します。WebRTC 送信は raw frame 経路です")
        }
    }

    func sendFrameTimestamp(_ message: FrameTimestampMessage) {
        queue.async { [weak self] in
            guard let self else {
                return
            }

            guard let json = message.jsonString(), let data = json.data(using: .utf8) else {
                Logger.warn("frame timestamp JSON を作成できません")
                return
            }

            if let dataChannel = self.dataChannel, dataChannel.readyState == .open {
                let sent = dataChannel.sendData(LKRTCDataBuffer(data: data, isBinary: false))
                if sent, (message.sequence == 1 || message.sequence % Int64(max(self.config.logEveryFrames, 1)) == 0) {
                    Logger.info("DataChannel frame-timestamp を送信しました: seq=\(message.sequence)")
                }
            } else if message.sequence == 1 || message.sequence % Int64(max(self.config.logEveryFrames, 1)) == 0 {
                Logger.warn("DataChannel が未openのため frame-timestamp を送れません: seq=\(message.sequence)")
            }
        }
    }

    private func ensurePeerConnection() {
        guard peerConnection == nil else {
            return
        }

        let rtcConfig = LKRTCConfiguration()
        rtcConfig.sdpSemantics = .unifiedPlan
        rtcConfig.iceServers = config.iceServers.map { LKRTCIceServer(urlStrings: [$0]) }

        let constraints = LKRTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
        )

        guard let createdPeerConnection = factory.peerConnection(with: rtcConfig, constraints: constraints, delegate: self) else {
            Logger.error("LKRTCPeerConnection を作成できません")
            return
        }

        let source = factory.videoSource()
        source.adaptOutputFormat(toWidth: config.width, height: config.height, fps: config.fps)
        let capturer = LKRTCVideoCapturer(delegate: source)
        let track = factory.videoTrack(with: source, trackId: "x5-video")
        createdPeerConnection.add(track, streamIds: ["x5-stream"])

        let dataChannelConfig = LKRTCDataChannelConfiguration()
        dataChannelConfig.isOrdered = false
        dataChannelConfig.maxRetransmits = 0
        let latencyChannel = createdPeerConnection.dataChannel(forLabel: "latency", configuration: dataChannelConfig)
        latencyChannel?.delegate = self

        peerConnection = createdPeerConnection
        videoSource = source
        videoCapturer = capturer
        dataChannel = latencyChannel

        Logger.info("LKRTCPeerConnection を作成しました: iceServers=\(config.iceServers.joined(separator: ","))")
    }

    private func createOffer() {
        ensurePeerConnection()
        guard let peerConnection else {
            return
        }

        let constraints = LKRTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "false",
                "OfferToReceiveVideo": "false"
            ],
            optionalConstraints: nil
        )

        peerConnection.offer(for: constraints) { [weak self] description, error in
            guard let self else {
                return
            }

            if let error {
                Logger.warn("offer 作成に失敗しました: \(error.localizedDescription)")
                return
            }

            guard let description else {
                Logger.warn("offer 作成結果が空でした")
                return
            }

            let preferredSDP = SDPCodecPreference.preferVideoCodecs(
                in: description.sdp,
                first: ["H265", "HEVC", "H264"]
            )
            let preferredDescription = LKRTCSessionDescription(type: .offer, sdp: preferredSDP)
            peerConnection.setLocalDescription(preferredDescription) { [weak self] error in
                if let error {
                    Logger.warn("local offer 設定に失敗しました: \(error.localizedDescription)")
                    return
                }

                Logger.info("local offer を設定しました: sdpBytes=\(preferredSDP.utf8.count)")
                self?.signalingClient?.sendOffer(sdp: preferredSDP)
                self?.logCodecLines(from: preferredSDP)
            }
        }
    }

    private func logCodecLines(from sdp: String) {
        let codecLines = sdp
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { $0.hasPrefix("a=rtpmap:") && ($0.uppercased().contains("H265") || $0.uppercased().contains("HEVC") || $0.uppercased().contains("H264")) }

        for line in codecLines {
            Logger.info("SDP codec候補: \(line)")
        }
    }

    private static func logSupportedCodecs(encoderFactory: LKRTCDefaultVideoEncoderFactory) {
        let codecNames = type(of: encoderFactory).supportedCodecs().map(\.name)
        Logger.info("LiveKitWebRTC encoder supported codecs: \(codecNames.joined(separator: ","))")
        if codecNames.contains(where: { $0.uppercased().contains("H265") || $0.uppercased().contains("HEVC") }) {
            Logger.info("LiveKitWebRTC encoder は HEVC/H.265 候補を公開しています")
        } else {
            Logger.warn("LiveKitWebRTC encoder の supportedCodecs に HEVC/H.265 が見えません。H.264 fallback 検証が必要です")
        }
    }
}

extension LiveKitWebRTCSenderAdapter: LKRTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange stateChanged: LKRTCSignalingState) {
        Logger.info("WebRTC signalingState=\(stateChanged.rawValue)")
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didAdd stream: LKRTCMediaStream) {
        Logger.info("WebRTC stream added: \(stream.streamId)")
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didRemove stream: LKRTCMediaStream) {
        Logger.info("WebRTC stream removed: \(stream.streamId)")
    }

    func peerConnectionShouldNegotiate(_ peerConnection: LKRTCPeerConnection) {
        Logger.info("WebRTC renegotiation requested")
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange newState: LKRTCIceConnectionState) {
        Logger.info("WebRTC iceConnectionState=\(newState.rawValue)")
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange newState: LKRTCIceGatheringState) {
        Logger.info("WebRTC iceGatheringState=\(newState.rawValue)")
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didGenerate candidate: LKRTCIceCandidate) {
        Logger.info("local ICE candidate を生成しました: sdpMid=\(candidate.sdpMid ?? "nil")")
        signalingClient?.sendIceCandidate(
            IceCandidatePayload(
                candidate: candidate.sdp,
                sdpMid: candidate.sdpMid,
                sdpMLineIndex: Int(candidate.sdpMLineIndex)
            )
        )
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didRemove candidates: [LKRTCIceCandidate]) {
        Logger.info("local ICE candidate が削除されました: count=\(candidates.count)")
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didOpen dataChannel: LKRTCDataChannel) {
        Logger.info("remote DataChannel opened: label=\(dataChannel.label)")
    }
}

extension LiveKitWebRTCSenderAdapter: LKRTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: LKRTCDataChannel) {
        Logger.info("DataChannel state changed: label=\(dataChannel.label) state=\(dataChannel.readyState.rawValue)")
    }

    func dataChannel(_ dataChannel: LKRTCDataChannel, didReceiveMessageWith buffer: LKRTCDataBuffer) {
        if let text = String(data: buffer.data, encoding: .utf8) {
            Logger.info("DataChannel message received: \(text)")
        } else {
            Logger.info("DataChannel binary message received: bytes=\(buffer.data.count)")
        }
    }
}
#endif
