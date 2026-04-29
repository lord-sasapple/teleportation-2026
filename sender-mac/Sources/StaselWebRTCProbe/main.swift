import Foundation
import WebRTC

final class ProbePeerConnectionDelegate: NSObject, RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("signalingState=\(stateChanged.rawValue)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        print("renegotiation requested")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        print("iceConnectionState=\(newState.rawValue)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        print("iceGatheringState=\(newState.rawValue)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        print("ice candidate generated: sdpMid=\(candidate.sdpMid ?? "nil")")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("data channel opened: \(dataChannel.label)")
    }
}

print("===== stasel/WebRTC HEVC probe =====")

RTCInitializeSSL()
defer {
    RTCCleanupSSL()
}

let encoderFactory = RTCDefaultVideoEncoderFactory()
let decoderFactory = RTCDefaultVideoDecoderFactory()

let encoderCodecs = type(of: encoderFactory).supportedCodecs()
let decoderCodecs = decoderFactory.supportedCodecs()

print("encoder supportedCodecs: \(encoderCodecs.map { $0.name }.joined(separator: ", "))")
print("decoder supportedCodecs: \(decoderCodecs.map { $0.name }.joined(separator: ", "))")

let hasEncoderHEVC = encoderCodecs.contains {
    $0.name.uppercased().contains("H265") || $0.name.uppercased().contains("HEVC")
}
let hasDecoderHEVC = decoderCodecs.contains {
    $0.name.uppercased().contains("H265") || $0.name.uppercased().contains("HEVC")
}

print("has encoder HEVC/H265: \(hasEncoderHEVC)")
print("has decoder HEVC/H265: \(hasDecoderHEVC)")

let factory = RTCPeerConnectionFactory(encoderFactory: encoderFactory, decoderFactory: decoderFactory)

let config = RTCConfiguration()
config.sdpSemantics = .unifiedPlan
config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]

let constraints = RTCMediaConstraints(
    mandatoryConstraints: nil,
    optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
)

let delegate = ProbePeerConnectionDelegate()

guard let peerConnection = factory.peerConnection(
    with: config,
    constraints: constraints,
    delegate: delegate
) else {
    print("RESULT: failed to create RTCPeerConnection")
    exit(1)
}

let videoSource = factory.videoSource()
videoSource.adaptOutputFormat(toWidth: 2880, height: 1440, fps: 30)

let videoTrack = factory.videoTrack(with: videoSource, trackId: "probe-video")
peerConnection.add(videoTrack, streamIds: ["probe-stream"])

let offerConstraints = RTCMediaConstraints(
    mandatoryConstraints: [
        "OfferToReceiveAudio": "false",
        "OfferToReceiveVideo": "false"
    ],
    optionalConstraints: nil
)

let semaphore = DispatchSemaphore(value: 0)

peerConnection.offer(for: offerConstraints) { description, error in
    if let error {
        print("RESULT: offer failed: \(error.localizedDescription)")
        semaphore.signal()
        return
    }

    guard let description else {
        print("RESULT: offer nil")
        semaphore.signal()
        return
    }

    let codecLines = description.sdp
        .split(whereSeparator: \.isNewline)
        .map(String.init)
        .filter {
            $0.hasPrefix("a=rtpmap:")
            && (
                $0.uppercased().contains("H265")
                || $0.uppercased().contains("HEVC")
                || $0.uppercased().contains("H264")
                || $0.uppercased().contains("AV1")
                || $0.uppercased().contains("VP9")
                || $0.uppercased().contains("VP8")
            )
        }

    print("offer codec lines:")
    for line in codecLines {
        print("  \(line)")
    }

    let hasSdpHEVC = codecLines.contains {
        $0.uppercased().contains("H265") || $0.uppercased().contains("HEVC")
    }

    print("has SDP HEVC/H265: \(hasSdpHEVC)")

    if hasEncoderHEVC && hasDecoderHEVC && hasSdpHEVC {
        print("RESULT: stasel/WebRTC exposes HEVC/H265 for macOS P2P")
    } else {
        print("RESULT: stasel/WebRTC does NOT expose complete HEVC/H265 path")
    }

    semaphore.signal()
}

_ = semaphore.wait(timeout: .now() + 10)

print("====================================")
