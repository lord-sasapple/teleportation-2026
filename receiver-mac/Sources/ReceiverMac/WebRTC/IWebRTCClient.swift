import Foundation
import CoreVideo

public protocol IWebRTCClient: AnyObject {
    var Log: ((String) -> Void)? { get set }
    var StatsUpdated: (([String: Any]) -> Void)? { get set }
    var VideoFrameReady: ((CVPixelBuffer) -> Void)? { get set }

    func initialize(preferredCodec: String)
    func setRemoteOffer(_ sdp: String)
    func addRemoteIceCandidate(_ candidate: [String: Any])
    func pollStats()
    func shutdown()
}

// Expose C shim functions
@_silgen_name("webrtc_shim_init")
func webrtc_shim_init(_ signaling_url: UnsafePointer<CChar>?, _ room: UnsafePointer<CChar>?)

@_silgen_name("webrtc_shim_set_preferred_codec")
func webrtc_shim_set_preferred_codec(_ codec: UnsafePointer<CChar>?)

@_silgen_name("webrtc_shim_set_remote_offer")
func webrtc_shim_set_remote_offer(_ sdp: UnsafePointer<CChar>?)

@_silgen_name("webrtc_shim_add_ice_candidate")
func webrtc_shim_add_ice_candidate(_ candidate_json: UnsafePointer<CChar>?)

@_silgen_name("webrtc_shim_shutdown")
func webrtc_shim_shutdown()
