import Foundation

enum WebRTCAdapterFactory {
    static func make(config: AppConfig, signalingClient: SignalingClient?) -> WebRTCSenderAdapter {
        #if HAS_WEBRTC
        return NativeWebRTCSenderAdapter(config: config, signalingClient: signalingClient)
        #else
        return NativeWebRTCSenderUnavailableAdapter(config: config)
        #endif
    }
}

