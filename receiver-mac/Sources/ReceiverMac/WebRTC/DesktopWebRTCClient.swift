import Foundation
import CoreVideo

// DesktopWebRTCClient: scaffold for integrating libwebrtc on macOS and display via VideoToolbox/AVSampleBufferDisplayLayer

public final class DesktopWebRTCClient {
    public var Log: ((String) -> Void)?
    public var StatsUpdated: (([String: Any]) -> Void)?
    public var VideoFrameReady: ((CVPixelBuffer) -> Void)?

    private var preferredCodec: String = "hevc"

    public init() {
        Log?("DesktopWebRTCClient initialized (scaffold)")
    }

    public func initialize(preferredCodec: String) {
        self.preferredCodec = preferredCodec
        Log?("DesktopWebRTCClient initialize: preferredCodec=\(preferredCodec)")
        // TODO: ここで libwebrtc の PeerConnection を初期化し、Video Track を受け取る
        // - libwebrtc を thirdparty として取り込み
        // - PeerConnection の callbacks で受信した RTP を libwebrtc がデコードするようにする
        // - デコード出力を CVPixelBuffer か CMSampleBuffer に変換して VideoFrameReady で渡す
    }

    public func setRemoteOffer(_ sdp: String) {
        Log?("setRemoteOffer called: sdpBytes=\(sdp.count)")
        // TODO: SDP を libwebrtc に渡して answer を作る
        // Call native shim (placeholder)
        webrtc_shim_set_remote_offer(sdp)
    }

    public func addRemoteIceCandidate(_ candidate: [String: Any]) {
        Log?("addRemoteIceCandidate called")
        // TODO: libwebrtc に ICE candidate を追加
        if let data = try? JSONSerialization.data(withJSONObject: candidate, options: []) {
            if let s = String(data: data, encoding: .utf8) {
                webrtc_shim_add_ice_candidate(s)
            }
        }
    }

    public func pollStats() {
        // TODO: libwebrtc の statsCollector を使って必要な指標を返す
        StatsUpdated?( ["placeholder": "stats"] )
    }

    public func shutdown() {
        Log?("DesktopWebRTCClient shutdown")
        webrtc_shim_shutdown()
    }
}
