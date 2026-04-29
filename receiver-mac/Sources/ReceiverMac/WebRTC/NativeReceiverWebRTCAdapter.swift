import AppKit
import CoreVideo
import Foundation

final class NativeReceiverWebRTCAdapter: ReceiverWebRTCAdapter {
    var onLocalAnswer: ((String) -> Void)?
    var onLocalIceCandidate: ((IceCandidatePayload) -> Void)?
    var onPreviewRendererView: ((NSView) -> Void)?
    var onDataChannelMessage: ((Data) -> Void)?
    var onFrame: ((CVPixelBuffer) -> Void)?

    private let desktopClient: DesktopWebRTCClient
    private let iceServers: [String]

    init(iceServers: [String]) {
        self.iceServers = iceServers
        self.desktopClient = DesktopWebRTCClient()
        self.desktopClient.Log = { Logger.info("DesktopClient: \($0)") }
        self.desktopClient.StatsUpdated = { stats in
            Logger.info("receiver stats: \(stats)")
        }
    }

    func start() {
        Logger.info("Native receiver scaffold を開始します: iceServers=\(iceServers.joined(separator: ","))")
        desktopClient.initialize(preferredCodec: "hevc")
    }

    func stop() {
        desktopClient.shutdown()
    }

    func setRemoteOffer(_ sdp: String) {
        desktopClient.setRemoteOffer(sdp)
        // Placeholder answer path until real libwebrtc bridge is wired.
        onLocalAnswer?("v=0\r\ns=-\r\n")
    }

    func addRemoteIceCandidate(_ candidate: IceCandidatePayload) {
        desktopClient.addRemoteIceCandidate([
            "candidate": candidate.candidate,
            "sdpMid": candidate.sdpMid as Any,
            "sdpMLineIndex": candidate.sdpMLineIndex as Any
        ])
    }

    func setPreferredCodec(_ codec: String) {
        desktopClient.initialize(preferredCodec: codec)
    }

    func pollStats() {
        desktopClient.pollStats()
    }
}
