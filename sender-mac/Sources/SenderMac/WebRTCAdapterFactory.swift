import Foundation

enum WebRTCAdapterFactory {
    static func make(config: AppConfig, signalingClient: SignalingClient?) -> WebRTCSenderAdapter {
        #if HAS_LIVEKIT_WEBRTC
        return LiveKitWebRTCSenderAdapter(config: config, signalingClient: signalingClient)
        #elseif HAS_WEBRTC
        return NativeWebRTCSenderAdapter(config: config, signalingClient: signalingClient)
        #else
        return NativeWebRTCSenderUnavailableAdapter(config: config)
        #endif
    }
}
