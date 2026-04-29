import CoreVideo
import Foundation

protocol ReceiverWebRTCAdapter: AnyObject {
    var onLocalAnswer: ((String) -> Void)? { get set }
    var onLocalIceCandidate: ((IceCandidatePayload) -> Void)? { get set }
    var onFrame: ((CVPixelBuffer) -> Void)? { get set }

    func start()
    func stop()
    func setRemoteOffer(_ sdp: String)
    func addRemoteIceCandidate(_ candidate: IceCandidatePayload)
    func setPreferredCodec(_ codec: String)
    func pollStats()
}
