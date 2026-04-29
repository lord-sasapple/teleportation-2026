import Foundation

enum ReceiverWebRTCAdapterFactory {
    static func make(config: AppConfig) -> ReceiverWebRTCAdapter {
#if HAS_LIVEKIT_WEBRTC
        Logger.info("WEBRTC_PROVIDER=livekit を検出。LiveKit receiver adapter を使用します")
        return LiveKitReceiverWebRTCAdapter(iceServers: config.iceServers)
#else
        Logger.warn("LiveKitWebRTC が利用できないため Native receiver scaffold を使用します")
        return NativeReceiverWebRTCAdapter(iceServers: config.iceServers)
#endif
    }
}
