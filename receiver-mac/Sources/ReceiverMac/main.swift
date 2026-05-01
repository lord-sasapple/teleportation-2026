import CoreVideo
import Foundation

final class ReceiverApp: @unchecked Sendable {
    private let config: AppConfig
    private let signalingClient: SignalingClient
    private let webRTC: ReceiverWebRTCAdapter
    private var viewer: Viewer360?
    private var running = true
    private var receivedFrames: Int64 = 0
    private var enqueuedViewerFrames: Int64 = 0
    private var skippedViewerFrames: Int64 = 0
    private var latestTimestamp: FrameTimestampMessage?
    private var latestTimestampReceiveTimeMs: Int64 = 0
    private var latestRenderFrame: ReceivedRenderFrame?
    private var viewerRenderTaskRunning = false
    private let latestFrameLock = NSLock()

    init(config: AppConfig) {
        self.config = config
        self.signalingClient = SignalingClient(baseURL: config.signalingURL, roomId: config.roomId)
        self.webRTC = ReceiverWebRTCAdapterFactory.make(config: config)
    }

    func run() {
        Logger.setMirror { [weak self] level, message in
            self?.signalingClient.sendReceiverLog(level: level, message: message)
        }

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

        webRTC.onDataChannelMessage = { [weak self] data in
            self?.handleDataChannelMessage(data)
        }

        webRTC.onFrame = { [weak self] pixelBuffer in
            self?.handleReceivedPixelBuffer(pixelBuffer)
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

    private func handleReceivedPixelBuffer(_ pixelBuffer: CVPixelBuffer) {
        receivedFrames += 1
        let frameCount = receivedFrames
        let nowMs = Self.nowMs()
        let renderFrame = ReceivedRenderFrame(
            pixelBuffer: pixelBuffer,
            sequence: frameCount,
            renderFrameCallbackTimeMs: nowMs,
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )

        if frameCount == 1 || frameCount % 30 == 0 {
            if let ts = latestTimestamp {
                let captureToRenderApprox = nowMs - ts.captureTimeMs
                let sendToRenderApprox = nowMs - ts.sendTimeMs
                let dataToRenderApprox = nowMs - latestTimestampReceiveTimeMs
                Logger.info("frame received: count=\(frameCount) size=\(renderFrame.width)x\(renderFrame.height) approxLatency captureToRender=\(captureToRenderApprox)ms sendToRender=\(sendToRenderApprox)ms dataToRender=\(dataToRenderApprox)ms tsSeq=\(ts.sequence)")
            } else {
                Logger.info("frame received: count=\(frameCount) size=\(renderFrame.width)x\(renderFrame.height) renderCallbackTimeMs=\(nowMs)")
            }
        }

        latestFrameLock.lock()
        if latestRenderFrame != nil {
            skippedViewerFrames += 1
        }
        latestRenderFrame = renderFrame
        let shouldStartRenderTask = !viewerRenderTaskRunning
        if shouldStartRenderTask {
            viewerRenderTaskRunning = true
        }
        let skipped = skippedViewerFrames
        latestFrameLock.unlock()

        if skipped > 0 && skipped % 30 == 0 {
            Logger.info("latency receiver latest-only: overwrittenBeforeViewer=\(skipped)")
        }

        if shouldStartRenderTask {
            scheduleViewerRenderLoop()
        }
    }

    private func scheduleViewerRenderLoop() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            while true {
                let frame = self.takeLatestRenderFrame()
                guard let frame else {
                    self.markViewerRenderTaskStopped()
                    return
                }

                let updateStartMs = Self.nowMs()
                let callbackToViewerStartMs = updateStartMs - frame.renderFrameCallbackTimeMs
                let result = self.viewer?.updateFrame(frame.pixelBuffer) ?? ViewerFrameUpdateResult.skipped(reason: "viewer nil")
                let updateEndMs = Self.nowMs()

                self.enqueuedViewerFrames += 1
                if frame.sequence == 1 || self.enqueuedViewerFrames % 30 == 0 || result.wasUpdated {
                    Logger.info(
                        "latency receiver viewer: seq=\(frame.sequence) callbackToViewerStart=\(callbackToViewerStartMs)ms updateDuration=\(updateEndMs - updateStartMs)ms totalCallbackToViewerEnd=\(updateEndMs - frame.renderFrameCallbackTimeMs)ms updated=\(result.wasUpdated) detail=\(result.detail) displayed=\(self.enqueuedViewerFrames) overwritten=\(self.skippedViewerFrames)"
                    )
                }
            }
        }
    }

    private func takeLatestRenderFrame() -> ReceivedRenderFrame? {
        latestFrameLock.lock()
        defer { latestFrameLock.unlock() }
        let frame = latestRenderFrame
        latestRenderFrame = nil
        return frame
    }

    private func markViewerRenderTaskStopped() {
        latestFrameLock.lock()
        viewerRenderTaskRunning = false
        let shouldRestart = latestRenderFrame != nil
        if shouldRestart {
            viewerRenderTaskRunning = true
        }
        latestFrameLock.unlock()

        if shouldRestart {
            scheduleViewerRenderLoop()
        }
    }

    private func handleDataChannelMessage(_ data: Data) {
        guard let message = try? JSONDecoder().decode(FrameTimestampMessage.self, from: data) else {
            if let text = String(data: data, encoding: .utf8) {
                Logger.warn("receiver DataChannel unknown message: \(text)")
            } else {
                Logger.warn("receiver DataChannel unknown binary message: bytes=\(data.count)")
            }
            return
        }

        guard message.type == "frame-timestamp" else {
            Logger.warn("receiver DataChannel unsupported message type=\(message.type)")
            return
        }

        let nowMs = Self.nowMs()
        latestTimestamp = message
        latestTimestampReceiveTimeMs = nowMs

        if message.sequence == 1 || message.sequence % 30 == 0 {
            Logger.info(
                "latency timestamp received: seq=\(message.sequence) captureToData=\(nowMs - message.captureTimeMs)ms sendToData=\(nowMs - message.sendTimeMs)ms encode=\(message.encodeEndTimeMs - message.encodeStartTimeMs)ms"
            )
        }
    }

    private static func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
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
        Logger.setMirror(nil)
        webRTC.stop()
        Task { @MainActor in
            self.viewer?.stop()
            self.viewer = nil
        }
    }
}

private struct ReceivedRenderFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let sequence: Int64
    let renderFrameCallbackTimeMs: Int64
    let width: Int
    let height: Int
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
