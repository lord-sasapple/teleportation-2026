#if HAS_WEBRTC
import CoreVideo
import Foundation
import WebRTC

final class NativeWebRTCSenderAdapter: NSObject, WebRTCSenderAdapter, @unchecked Sendable {
    private let config: AppConfig
    private weak var signalingClient: SignalingClient?
    private var hasLoggedEncodedFrame = false
    private let queue = DispatchQueue(label: "telepresence.sender.webrtc")
    private let factory: RTCPeerConnectionFactory
    private var peerConnection: RTCPeerConnection?
    private var videoSource: RTCVideoSource?
    private var videoCapturer: RTCVideoCapturer?
    private var dataChannel: RTCDataChannel?

    init(config: AppConfig, signalingClient: SignalingClient?) {
        self.config = config
        self.signalingClient = signalingClient
        RTCInitializeSSL()
        factory = RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory()
        )
        super.init()
    }

    deinit {
        RTCCleanupSSL()
    }

    func start() {
        Logger.info("libwebrtc native framework を検出しました")
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
        Logger.info("Native WebRTC adapter を停止しました")
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
            guard let self, let peerConnection else {
                Logger.warn("answer 受信時点で PeerConnection がありません")
                return
            }

            let description = RTCSessionDescription(type: .answer, sdp: sdp)
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

            let rtcCandidate = RTCIceCandidate(
                sdp: candidate.candidate,
                sdpMLineIndex: Int32(candidate.sdpMLineIndex ?? 0),
                sdpMid: candidate.sdpMid
            )
            peerConnection.add(rtcCandidate)
            Logger.info("remote ICE candidate を追加しました: candidateBytes=\(candidate.candidate.utf8.count)")
        }
    }

    func handlePeerLeft(role: SignalingRole) {
        Logger.info("WebRTC native adapter が peer-left を受信しました: role=\(role.rawValue)")
    }

    func sendRawFrame(_ frame: RawVideoFrame) {
        queue.async { [weak self] in
            guard let self, let videoSource, let videoCapturer else {
                return
            }

            let buffer = RTCCVPixelBuffer(pixelBuffer: frame.pixelBuffer)
            let videoFrame = RTCVideoFrame(buffer: buffer, rotation: ._0, timeStampNs: frame.presentationTimeNs)
            videoSource.capturer(videoCapturer, didCapture: videoFrame)

            if frame.sequence == 1 || frame.sequence % Int64(max(self.config.logEveryFrames, 1)) == 0 {
                Logger.info("raw frame を WebRTC video source へ渡しました: seq=\(frame.sequence) \(frame.width)x\(frame.height)")
            }
        }
    }

    func sendEncodedFrame(_ frame: EncodedVideoFrame) {
        if !hasLoggedEncodedFrame {
            hasLoggedEncodedFrame = true
            Logger.info("encoded CMSampleBuffer は VideoToolbox 計測用として保持します。WebRTC 送信は raw RTCVideoFrame 経路です")
        }

        if frame.log.sequence == 1 || frame.log.sequence % Int64(max(config.logEveryFrames, 1)) == 0 {
            Logger.info("native WebRTC frame bridge pending: seq=\(frame.log.sequence) bytes=\(frame.log.sizeBytes) codec=\(frame.log.codec.displayName)")
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
                dataChannel.sendData(RTCDataBuffer(data: data, isBinary: false))
                if message.sequence == 1 || message.sequence % Int64(max(self.config.logEveryFrames, 1)) == 0 {
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

        let rtcConfig = RTCConfiguration()
        rtcConfig.sdpSemantics = .unifiedPlan
        rtcConfig.iceServers = config.iceServers.map { RTCIceServer(urlStrings: [$0]) }

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: [
                "DtlsSrtpKeyAgreement": "true"
            ]
        )

        guard let createdPeerConnection = factory.peerConnection(with: rtcConfig, constraints: constraints, delegate: self) else {
            Logger.error("RTCPeerConnection を作成できません")
            return
        }

        let source = factory.videoSource()
        let capturer = RTCVideoCapturer(delegate: source)
        let track = factory.videoTrack(with: source, trackId: "x5-video")
        createdPeerConnection.add(track, streamIds: ["x5-stream"])

        let dataChannelConfig = RTCDataChannelConfiguration()
        dataChannelConfig.isOrdered = false
        dataChannelConfig.maxRetransmits = 0
        let latencyChannel = createdPeerConnection.dataChannel(forLabel: "latency", configuration: dataChannelConfig)
        latencyChannel?.delegate = self

        peerConnection = createdPeerConnection
        videoSource = source
        videoCapturer = capturer
        dataChannel = latencyChannel

        Logger.info("RTCPeerConnection を作成しました: iceServers=\(config.iceServers.joined(separator: ","))")
    }

    private func createOffer() {
        ensurePeerConnection()
        guard let peerConnection else {
            return
        }

        let constraints = RTCMediaConstraints(
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
            let preferredDescription = RTCSessionDescription(type: .offer, sdp: preferredSDP)
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
}

extension NativeWebRTCSenderAdapter: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        Logger.info("WebRTC signalingState=\(stateChanged.rawValue)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        Logger.info("WebRTC stream added: \(stream.streamId)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        Logger.info("WebRTC stream removed: \(stream.streamId)")
    }

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        Logger.info("WebRTC renegotiation requested")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        Logger.info("WebRTC iceConnectionState=\(newState.rawValue)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        Logger.info("WebRTC iceGatheringState=\(newState.rawValue)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        Logger.info("local ICE candidate を生成しました: sdpMid=\(candidate.sdpMid ?? "nil")")
        signalingClient?.sendIceCandidate(
            IceCandidatePayload(
                candidate: candidate.sdp,
                sdpMid: candidate.sdpMid,
                sdpMLineIndex: Int(candidate.sdpMLineIndex)
            )
        )
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        Logger.info("local ICE candidate が削除されました: count=\(candidates.count)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        Logger.info("remote DataChannel opened: label=\(dataChannel.label)")
    }
}

extension NativeWebRTCSenderAdapter: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        Logger.info("DataChannel state changed: label=\(dataChannel.label) state=\(dataChannel.readyState.rawValue)")
    }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        if let text = String(data: buffer.data, encoding: .utf8) {
            Logger.info("DataChannel message received: \(text)")
        } else {
            Logger.info("DataChannel binary message received: bytes=\(buffer.data.count)")
        }
    }
}
#endif
