#if HAS_LIVEKIT_WEBRTC
import AppKit
import CoreVideo
import Foundation
@preconcurrency import LiveKitWebRTC

final class LiveKitReceiverWebRTCAdapter: NSObject, ReceiverWebRTCAdapter, @unchecked Sendable {
    var onLocalAnswer: ((String) -> Void)?
    var onLocalIceCandidate: ((IceCandidatePayload) -> Void)?
    var onPreviewRendererView: ((NSView) -> Void)?
    var onDataChannelMessage: ((Data) -> Void)?
    var onFrame: ((CVPixelBuffer) -> Void)?

    private let queue = DispatchQueue(label: "telepresence.receiver.livekit-webrtc")
    private let factory: LKRTCPeerConnectionFactory
    private let iceServers: [String]
    private var peerConnection: LKRTCPeerConnection?
    private var preferredCodec: String = "hevc"
    private let frameRenderer = PixelBufferFrameRenderer()
    private var attachedVideoTrack: LKRTCVideoTrack?

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

            self.logVideoSessionLines(from: sdp, label: "remote offer")
            let description = LKRTCSessionDescription(type: .offer, sdp: sdp)
            pc.setRemoteDescription(description) { error in
                if let error {
                    Logger.error("remote offer 設定に失敗しました: \(error.localizedDescription)")
                    return
                }
                self.logTransceivers("remote offer 設定後")
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
        guard let peerConnection else {
            Logger.info("receiver stats: PeerConnection 未作成")
            return
        }

        peerConnection.statistics { report in
            let lines = Self.receiverStatsSummaries(from: report)

            if lines.isEmpty {
                Logger.info("receiver stats: video inbound/track/candidate 情報なし")
            } else {
                for line in lines.prefix(12) {
                    Logger.info(line)
                }
            }
        }
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
            self.logVideoSessionLines(from: description.sdp, label: "local answer")
            peerConnection.setLocalDescription(description) { [weak self] error in
                guard let self else { return }

                if let error {
                    Logger.error("local answer 設定に失敗しました: \(error.localizedDescription)")
                    return
                }

                self.logTransceivers("local answer 設定後")
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

    private func logVideoSessionLines(from sdp: String, label: String) {
        let lines = sdp.split(whereSeparator: \.isNewline).map(String.init)
        guard let mediaIndex = lines.firstIndex(where: { $0.hasPrefix("m=video ") }) else {
            Logger.warn("\(label) SDP に m=video がありません")
            return
        }

        Logger.info("\(label) SDP video m-line: \(lines[mediaIndex])")
        for line in lines[(mediaIndex + 1)...].prefix(24) {
            if line.hasPrefix("m=") {
                break
            }
            if line.hasPrefix("a=sendrecv") ||
                line.hasPrefix("a=sendonly") ||
                line.hasPrefix("a=recvonly") ||
                line.hasPrefix("a=inactive") ||
                line.hasPrefix("a=mid:") ||
                line.hasPrefix("a=msid:") {
                Logger.info("\(label) SDP video: \(line)")
            }
        }
    }

    private func logTransceivers(_ prefix: String) {
        guard let peerConnection else {
            return
        }

        for (index, transceiver) in peerConnection.transceivers.enumerated() {
            var currentDirection = LKRTCRtpTransceiverDirection.inactive
            let hasCurrentDirection = transceiver.currentDirection(&currentDirection)
            let track = transceiver.receiver.track
            let trackSummary: String
            if let track {
                trackSummary = "\(track.kind)/\(track.trackId) enabled=\(track.isEnabled) readyState=\(track.readyState.rawValue)"
            } else {
                trackSummary = "nil"
            }
            Logger.info(
                "\(prefix) transceiver[\(index)]: mid=\(transceiver.mid) mediaType=\(transceiver.mediaType.rawValue) direction=\(transceiver.direction.rawValue) current=\(hasCurrentDirection ? String(currentDirection.rawValue) : "nil") receiverTrack=\(trackSummary)"
            )
        }
    }

    private static func receiverStatsSummaries(from report: LKRTCStatisticsReport) -> [String] {
        var localCandidates: [String: LKRTCStatistics] = [:]
        var remoteCandidates: [String: LKRTCStatistics] = [:]

        for stat in report.statistics.values {
            if stat.type == "local-candidate" {
                localCandidates[stat.id] = stat
            } else if stat.type == "remote-candidate" {
                remoteCandidates[stat.id] = stat
            }
        }

        return report.statistics.values
            .sorted { lhs, rhs in
                if lhs.type == rhs.type {
                    return lhs.id < rhs.id
                }
                return lhs.type < rhs.type
            }
            .compactMap { stat in
                receiverStatsSummary(
                    for: stat,
                    localCandidates: localCandidates,
                    remoteCandidates: remoteCandidates
                )
            }
    }

    private static func candidateDescription(_ stat: LKRTCStatistics?) -> String {
        guard let stat else {
            return "-"
        }

        let values = stat.values

        func value(_ keys: [String]) -> String? {
            for key in keys {
                if let v = values[key] as? NSString {
                    return v as String
                }
                if let v = values[key] as? String {
                    return v
                }
                if let v = values[key] as? NSNumber {
                    return v.stringValue
                }
            }
            return nil
        }

        let type = value(["candidateType", "type"]) ?? "unknown"
        let protocolName = value(["protocol", "relayProtocol"]) ?? "-"
        let address = value(["address", "ip"]) ?? "-"
        let port = value(["port"]) ?? "-"
        return "\(type) \(protocolName) \(address):\(port)"
    }

    private static func receiverStatsSummary(
        for stat: LKRTCStatistics,
        localCandidates: [String: LKRTCStatistics],
        remoteCandidates: [String: LKRTCStatistics]
    ) -> String? {
        let values = stat.values

        func number(_ key: String) -> String? {
            if let value = values[key] as? NSNumber {
                return value.stringValue
            }
            if let value = values[key] as? NSString {
                return value as String
            }
            if let value = values[key] as? String {
                return value
            }
            return nil
        }

        func string(_ key: String) -> String? {
            if let value = values[key] as? NSString {
                return value as String
            }
            if let value = values[key] as? String {
                return value
            }
            if let value = values[key] as? NSNumber {
                return value.stringValue
            }
            return nil
        }

        switch stat.type {
        case "inbound-rtp":
            guard string("kind") == "video" || string("mediaType") == "video" else {
                return nil
            }
            return "receiver stats inbound-rtp: id=\(stat.id) bytes=\(number("bytesReceived") ?? "-") packets=\(number("packetsReceived") ?? "-") framesDecoded=\(number("framesDecoded") ?? "-") framesReceived=\(number("framesReceived") ?? "-") keyFrames=\(number("keyFramesDecoded") ?? "-") jitter=\(number("jitter") ?? "-") drops=\(number("framesDropped") ?? "-")"
        case "track":
            guard string("kind") == "video" || stat.id.lowercased().contains("video") else {
                return nil
            }
            return "receiver stats track: id=\(stat.id) width=\(number("frameWidth") ?? "-") height=\(number("frameHeight") ?? "-") fps=\(number("framesPerSecond") ?? "-") framesReceived=\(number("framesReceived") ?? "-") framesDecoded=\(number("framesDecoded") ?? "-")"
        case "candidate-pair":
            guard number("nominated") == "1" || number("selected") == "1" || string("state") == "succeeded" else {
                return nil
            }

            let localId = string("localCandidateId")
            let remoteId = string("remoteCandidateId")
            let local = localId.flatMap { localCandidates[$0] }
            let remote = remoteId.flatMap { remoteCandidates[$0] }

            return "receiver stats candidate-pair: id=\(stat.id) state=\(string("state") ?? "-") rtt=\(number("currentRoundTripTime") ?? "-") bytesRecv=\(number("bytesReceived") ?? "-") bytesSent=\(number("bytesSent") ?? "-") local=\(candidateDescription(local)) remote=\(candidateDescription(remote))"
        case "transport":
            return "receiver stats transport: id=\(stat.id) selectedPair=\(string("selectedCandidatePairId") ?? "-") dtls=\(string("dtlsState") ?? "-") bytesRecv=\(number("bytesReceived") ?? "-") bytesSent=\(number("bytesSent") ?? "-")"
        case "codec":
            let mime = string("mimeType") ?? ""
            guard mime.lowercased().contains("video") || mime.uppercased().contains("H264") || mime.uppercased().contains("H265") || mime.uppercased().contains("HEVC") else {
                return nil
            }
            return "receiver stats codec: id=\(stat.id) mime=\(mime) payload=\(number("payloadType") ?? "-")"
        default:
            return nil
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
            track.isEnabled = true
            track.shouldReceive = true
            attachedVideoTrack?.remove(frameRenderer)
            attachedVideoTrack = track
            track.add(frameRenderer)
            Logger.info("receiver video track renderer を接続しました: trackId=\(track.trackId) enabled=\(track.isEnabled) shouldReceive=\(track.shouldReceive) readyState=\(track.readyState.rawValue)")
            logTransceivers("renderer 接続時")
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
        dataChannel.delegate = self
        Logger.info("receiver data channel opened: \(dataChannel.label)")
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didStartReceivingOn transceiver: LKRTCRtpTransceiver) {
        Logger.info("receiver didStartReceivingOnTransceiver: mid=\(transceiver.mid) mediaType=\(transceiver.mediaType.rawValue)")
    }
}

extension LiveKitReceiverWebRTCAdapter: LKRTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: LKRTCDataChannel) {
        Logger.info("receiver DataChannel state changed: label=\(dataChannel.label) state=\(dataChannel.readyState.rawValue)")
    }

    func dataChannel(_ dataChannel: LKRTCDataChannel, didReceiveMessageWith buffer: LKRTCDataBuffer) {
        onDataChannelMessage?(buffer.data)
    }
}

private final class PixelBufferFrameRenderer: NSObject, LKRTCVideoRenderer {
    var onPixelBuffer: ((CVPixelBuffer) -> Void)?
    private var renderedFrames: Int64 = 0
    private var convertedI420Frames: Int64 = 0
    private var conversionFailures: Int64 = 0

    func setSize(_ size: CGSize) {
        Logger.info("receiver renderer size=\(Int(size.width))x\(Int(size.height))")
    }

    func renderFrame(_ frame: LKRTCVideoFrame?) {
        guard let frame else {
            return
        }

        renderedFrames += 1
        if renderedFrames == 1 || renderedFrames % 30 == 0 {
            Logger.info(
                "receiver renderFrame: count=\(renderedFrames) buffer=\(String(describing: type(of: frame.buffer))) size=\(frame.buffer.width)x\(frame.buffer.height) rotation=\(frame.rotation.rawValue)"
            )
        }

        if let cvBuffer = frame.buffer as? LKRTCCVPixelBuffer {
            onPixelBuffer?(cvBuffer.pixelBuffer)
            return
        }

        let i420Buffer = frame.buffer.toI420()
        guard let pixelBuffer = convertI420ToBGRA(i420Buffer) else {
            conversionFailures += 1
            if conversionFailures == 1 || conversionFailures % 30 == 0 {
                Logger.warn("receiver I420 -> BGRA 変換に失敗しました: failures=\(conversionFailures)")
            }
            return
        }

        convertedI420Frames += 1
        if convertedI420Frames == 1 || convertedI420Frames % 30 == 0 {
            Logger.info("receiver I420 frame を BGRA CVPixelBuffer に変換しました: count=\(convertedI420Frames)")
        }
        onPixelBuffer?(pixelBuffer)
    }

    private func convertI420ToBGRA(_ i420Buffer: any LKRTCI420BufferProtocol) -> CVPixelBuffer? {
        let width = Int(i420Buffer.width)
        let height = Int(i420Buffer.height)
        guard width > 0, height > 0 else {
            return nil
        }

        let attributes: CFDictionary = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ] as CFDictionary

        var output: CVPixelBuffer?
        let createStatus = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes,
            &output
        )
        guard createStatus == kCVReturnSuccess, let output else {
            Logger.warn("receiver BGRA CVPixelBuffer を作成できません: status=\(createStatus)")
            return nil
        }

        CVPixelBufferLockBaseAddress(output, [])
        defer {
            CVPixelBufferUnlockBaseAddress(output, [])
        }

        guard let baseAddress = CVPixelBufferGetBaseAddress(output)?.assumingMemoryBound(to: UInt8.self) else {
            return nil
        }

        let convertStatus = LKRTCYUVHelper.i420(
            toBGRA: i420Buffer.dataY,
            srcStrideY: i420Buffer.strideY,
            srcU: i420Buffer.dataU,
            srcStrideU: i420Buffer.strideU,
            srcV: i420Buffer.dataV,
            srcStrideV: i420Buffer.strideV,
            dstBGRA: baseAddress,
            dstStrideBGRA: Int32(CVPixelBufferGetBytesPerRow(output)),
            width: i420Buffer.width,
            height: i420Buffer.height
        )

        guard convertStatus == 0 else {
            Logger.warn("receiver I420 -> BGRA 変換エラー: status=\(convertStatus)")
            return nil
        }

        return output
    }
}
#endif
