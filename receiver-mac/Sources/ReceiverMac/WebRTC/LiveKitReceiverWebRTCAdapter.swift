#if HAS_LIVEKIT_WEBRTC
import CoreVideo
import Foundation
@preconcurrency import LiveKitWebRTC

final class LiveKitReceiverWebRTCAdapter: NSObject, ReceiverWebRTCAdapter, @unchecked Sendable {
    var onLocalAnswer: ((String) -> Void)?
    var onLocalIceCandidate: ((IceCandidatePayload) -> Void)?
    var onFrame: ((CVPixelBuffer) -> Void)?

    private let queue = DispatchQueue(label: "telepresence.receiver.livekit-webrtc")
    private let factory: LKRTCPeerConnectionFactory
    private let iceServers: [String]
    private var peerConnection: LKRTCPeerConnection?
    private var preferredCodec: String = "hevc"
    private let frameRenderer = PixelBufferFrameRenderer()
    private weak var attachedVideoTrack: LKRTCVideoTrack?

    init(iceServers: [String]) {
        self.iceServers = iceServers
        LKRTCInitializeSSL()
        let encoderFactory = LKRTCDefaultVideoEncoderFactory()
        let decoderFactory = LKRTCDefaultVideoDecoderFactory()
        self.factory = LKRTCPeerConnectionFactory(encoderFactory: encoderFactory, decoderFactory: decoderFactory)
        super.init()
        frameRenderer.onPixelBuffer = { [weak self] pixelBuffer in
            self?.onFrame?(pixelBuffer)
        }
    }

    deinit {
        LKRTCCleanupSSL()
    }

    func start() {
        queue.async { [weak self] in
            self?.ensurePeerConnection()
        }
    }

    func stop() {
        queue.sync {
            if let track = attachedVideoTrack {
                track.remove(frameRenderer)
                attachedVideoTrack = nil
            }
            peerConnection?.close()
            peerConnection = nil
        }
    }

    func setRemoteOffer(_ sdp: String) {
        queue.async { [weak self] in
            guard let self else { return }
            self.ensurePeerConnection()
            guard let pc = self.peerConnection else { return }

            let description = LKRTCSessionDescription(type: .offer, sdp: sdp)
            pc.setRemoteDescription(description) { error in
                if let error {
                    Logger.error("remote offer 設定に失敗しました: \(error.localizedDescription)")
                    return
                }
                self.createAnswer(peerConnection: pc)
            }
        }
    }

    func addRemoteIceCandidate(_ candidate: IceCandidatePayload) {
        queue.async { [weak self] in
            guard let pc = self?.peerConnection else { return }

            let rtcCandidate = LKRTCIceCandidate(
                sdp: candidate.candidate,
                sdpMLineIndex: Int32(candidate.sdpMLineIndex ?? 0),
                sdpMid: candidate.sdpMid
            )

            pc.add(rtcCandidate) { error in
                if let error {
                    Logger.warn("remote ICE candidate 追加に失敗: \(error.localizedDescription)")
                }
            }
        }
    }

    func setPreferredCodec(_ codec: String) {
        preferredCodec = codec.lowercased()
    }

    func pollStats() {
        Logger.info("LiveKit receiver stats polling (placeholder)")
    }

    private func ensurePeerConnection() {
        guard peerConnection == nil else { return }

        let rtcConfig = LKRTCConfiguration()
        rtcConfig.sdpSemantics = .unifiedPlan
        rtcConfig.iceServers = iceServers.map { LKRTCIceServer(urlStrings: [$0]) }

        let constraints = LKRTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
        )

        guard let created = factory.peerConnection(with: rtcConfig, constraints: constraints, delegate: self) else {
            Logger.error("receiver PeerConnection を作成できません")
            return
        }

        peerConnection = created
        Logger.info("receiver PeerConnection を作成しました (LiveKit): iceServers=\(iceServers.joined(separator: ","))")
    }

    private func createAnswer(peerConnection: LKRTCPeerConnection) {
        let constraints = LKRTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "false",
                "OfferToReceiveVideo": "true"
            ],
            optionalConstraints: nil
        )

        peerConnection.answer(for: constraints) { [weak self] description, error in
            guard let self else { return }
            if let error {
                Logger.error("answer 作成に失敗しました: \(error.localizedDescription)")
                return
            }

            guard let description else {
                Logger.error("answer が空でした")
                return
            }

            self.logCodecLines(from: description.sdp)
            peerConnection.setLocalDescription(description) { [weak self] error in
                guard let self else { return }

                if let error {
                    Logger.error("local answer 設定に失敗しました: \(error.localizedDescription)")
                    return
                }

                self.onLocalAnswer?(description.sdp)
                Logger.info("local answer を送信準備しました: sdpBytes=\(description.sdp.utf8.count)")
            }
        }
    }

    private func logCodecLines(from sdp: String) {
        let codecLines = sdp
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { $0.hasPrefix("a=rtpmap:") && ($0.uppercased().contains("H265") || $0.uppercased().contains("HEVC") || $0.uppercased().contains("H264")) }

        if codecLines.isEmpty {
            Logger.warn("receiver answer SDP に H265/HEVC/H264 の codec 行が見つかりません")
            return
        }

        for line in codecLines {
            Logger.info("receiver answer codec候補: \(line)")
        }
    }
}

extension LiveKitReceiverWebRTCAdapter: LKRTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange stateChanged: LKRTCSignalingState) {
        Logger.info("receiver signalingState=\(stateChanged.rawValue)")
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didAdd stream: LKRTCMediaStream) {
        Logger.info("receiver stream added: \(stream.streamId)")
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection,
                        didAdd rtpReceiver: LKRTCRtpReceiver,
                        streams mediaStreams: [LKRTCMediaStream]) {
        if let track = rtpReceiver.track as? LKRTCVideoTrack {
            attachedVideoTrack?.remove(frameRenderer)
            attachedVideoTrack = track
            track.add(frameRenderer)
            Logger.info("receiver video track renderer を接続しました")
        }
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didRemove stream: LKRTCMediaStream) {
        Logger.info("receiver stream removed: \(stream.streamId)")
    }

    func peerConnectionShouldNegotiate(_ peerConnection: LKRTCPeerConnection) {
        Logger.info("receiver renegotiation requested")
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange newState: LKRTCIceConnectionState) {
        Logger.info("receiver iceConnectionState=\(newState.rawValue)")
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange newState: LKRTCIceGatheringState) {
        Logger.info("receiver iceGatheringState=\(newState.rawValue)")
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didGenerate candidate: LKRTCIceCandidate) {
        onLocalIceCandidate?(
            IceCandidatePayload(
                candidate: candidate.sdp,
                sdpMid: candidate.sdpMid,
                sdpMLineIndex: Int(candidate.sdpMLineIndex)
            )
        )
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didRemove candidates: [LKRTCIceCandidate]) {
        Logger.info("receiver local ICE candidate removed: count=\(candidates.count)")
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didRemove rtpReceiver: LKRTCRtpReceiver) {
        if let track = rtpReceiver.track as? LKRTCVideoTrack {
            track.remove(frameRenderer)
            if attachedVideoTrack === track {
                attachedVideoTrack = nil
            }
        }
        Logger.info("receiver video track renderer を切断しました")
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didOpen dataChannel: LKRTCDataChannel) {
        Logger.info("receiver data channel opened: \(dataChannel.label)")
    }
}

private final class PixelBufferFrameRenderer: NSObject, LKRTCVideoRenderer {
    var onPixelBuffer: ((CVPixelBuffer) -> Void)?

    func setSize(_ size: CGSize) {
        // no-op
    }

    func renderFrame(_ frame: LKRTCVideoFrame?) {
        guard let frame,
              let cvBuffer = frame.buffer as? LKRTCCVPixelBuffer else {
            return
        }

        onPixelBuffer?(cvBuffer.pixelBuffer)
    }
}
#endif
