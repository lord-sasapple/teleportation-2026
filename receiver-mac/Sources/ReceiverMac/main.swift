import CoreVideo
import Foundation

final class ReceiverApp: @unchecked Sendable {
    private let config: AppConfig
    private let signalingClient: SignalingClient
    private let webRTC: ReceiverWebRTCAdapter
    private var viewer: Viewer360?
    private var running = true
    private var receivedFrames: Int64 = 0

    init(config: AppConfig) {
        self.config = config
        self.signalingClient = SignalingClient(baseURL: config.signalingURL, roomId: config.roomId)
        self.webRTC = ReceiverWebRTCAdapterFactory.make(config: config)
    }

    func run() {
        Logger.info("receiver-mac を起動します")
        Logger.info("room=\(config.roomId) codec=\(config.preferredCodec) signalingOnly=\(config.signalingOnly)")
        Logger.info("iceServers=\(config.iceServers.joined(separator: ","))")

        webRTC.onLocalAnswer = { [weak self] sdp in
            self?.signalingClient.sendAnswer(sdp: sdp)
        }
        webRTC.onLocalIceCandidate = { [weak self] candidate in
            self?.signalingClient.sendIceCandidate(candidate)
        }
        webRTC.onPreviewRendererView = { [weak self] previewView in
            Task { @MainActor [weak self] in
                self?.viewer?.showPreviewRendererView(previewView)
            }
        }

        webRTC.onFrame = { [weak self] pixelBuffer in
            guard let self else { return }
            self.receivedFrames += 1
            let frameCount = self.receivedFrames
            if frameCount == 1 || frameCount % 30 == 0 {
                Logger.info("frame received: count=\(frameCount) size=\(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer))")
            }

            let sendablePixelBuffer = SendablePixelBuffer(pixelBuffer)
            Task { @MainActor [weak self] in
                self?.viewer?.updateFrame(sendablePixelBuffer.value)
            }
        }

        signalingClient.onMessage = { [weak self] message in
            self?.handleSignalingMessage(message)
        }

        webRTC.setPreferredCodec(config.preferredCodec)
        webRTC.start()
        if !config.signalingOnly {
            Task { @MainActor in
                let viewer = Viewer360()
                viewer.start()
                self.viewer = viewer
            }
        }
        signalingClient.connect()

        if config.duration > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(config.duration)) { [weak self] in
                self?.stop()
            }
        }

        statsLoop()
        waitUntilStopped()
    }

    private func handleSignalingMessage(_ message: SignalingServerMessage) {
        switch message {
        case .joined(let roomId, let role):
            Logger.info("joined room=\(roomId) role=\(role.rawValue)")
        case .peerJoined(let role):
            Logger.info("peer joined role=\(role.rawValue)")
        case .offer(let sdp):
            Logger.info("offer を受信しました: sdpBytes=\(sdp.utf8.count)")
            webRTC.setRemoteOffer(sdp)
        case .iceCandidate(let candidate):
            webRTC.addRemoteIceCandidate(candidate)
        case .peerLeft(let role):
            Logger.warn("peer left role=\(role.rawValue)")
        case .answer:
            Logger.warn("receiver で answer を受信しました（無視）")
        case .pong:
            Logger.info("pong")
        case .error(let message):
            Logger.error("signaling error: \(message)")
        case .unknown(let type):
            Logger.warn("unknown signaling message type=\(type)")
        }
    }

    private func statsLoop() {
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            while self.running {
                self.webRTC.pollStats()
                Thread.sleep(forTimeInterval: TimeInterval(self.config.logEverySeconds))
            }
        }
    }

    private func waitUntilStopped() {
        while running {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }

    private func stop() {
        guard running else { return }
        running = false
        Logger.info("receiver-mac を停止します")
        signalingClient.disconnect()
        webRTC.stop()
        Task { @MainActor in
            self.viewer?.stop()
            self.viewer = nil
        }
    }
}

private struct SendablePixelBuffer: @unchecked Sendable {
    let value: CVPixelBuffer

    init(_ value: CVPixelBuffer) {
        self.value = value
    }
}

do {
    let config = try AppConfig.parse(from: CommandLine.arguments)
    let app = ReceiverApp(config: config)
    app.run()
} catch {
    Logger.error(error.localizedDescription)
    AppConfig.usage()
    exit(1)
}
