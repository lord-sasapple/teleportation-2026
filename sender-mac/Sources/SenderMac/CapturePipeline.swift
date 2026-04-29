import AVFoundation
import CoreVideo
import Foundation

final class CapturePipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let config: AppConfig
    private let session = AVCaptureSession()
    private let captureQueue = DispatchQueue(label: "telepresence.sender.capture")
    private let encoder: VideoEncoder
    private let statsMonitor: SenderStatsMonitor
    private var sequence: Int64 = 0
    private var droppedCaptureFrames: Int64 = 0
    private var nextAcceptedMonotonicMs: Double?
    private var lastDropLogMonotonicMs: Double = 0
    private var isRunning = false
    private var rawFrameHandler: (@Sendable (RawVideoFrame) -> Void)?
    private var stopHandler: (@Sendable () -> Void)?

    init(
        config: AppConfig,
        device: AVCaptureDevice,
        rawFrameHandler: (@Sendable (RawVideoFrame) -> Void)? = nil,
        encodedFrameHandler: (@Sendable (EncodedVideoFrame) -> Void)? = nil,
        stopHandler: (@Sendable () -> Void)? = nil
    ) throws {
        self.config = config
        self.rawFrameHandler = rawFrameHandler
        self.stopHandler = stopHandler

        let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        encoder = try VideoEncoder(config: config, width: dimensions.width, height: dimensions.height)
        statsMonitor = SenderStatsMonitor(codec: config.codec, logEveryFrames: config.logEveryFrames)

        super.init()

        let wrappedEncodedFrameHandler = encodedFrameHandler
        encoder.encodedFrameHandler = { [weak self] frame in
            self?.statsMonitor.recordEncodedFrame(frame.log)
            wrappedEncodedFrameHandler?(frame)
        }

        try configureSession(device: device)
    }

    func start() {
        guard !isRunning else {
            return
        }

        isRunning = true
        session.startRunning()
        Logger.info("capture session を開始しました")
    }

    func stop() {
        guard isRunning else {
            return
        }

        isRunning = false
        session.stopRunning()
        encoder.finish()
        statsMonitor.printFinalStats()
        Logger.info("capture session を停止しました")
    }

    func getStatsMonitor() -> SenderStatsMonitor {
        statsMonitor
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let nowMonotonicMs = Clock.monotonicMs()
        let targetFrameIntervalMs = 1000.0 / Double(max(config.fps, 1))
        if let nextAcceptedMonotonicMs,
           nowMonotonicMs + 0.5 < nextAcceptedMonotonicMs {
            droppedCaptureFrames += 1
            if nowMonotonicMs - lastDropLogMonotonicMs >= 1000 {
                Logger.info("capture fps gate dropped=\(droppedCaptureFrames) targetFps=\(config.fps)")
                lastDropLogMonotonicMs = nowMonotonicMs
            }
            return
        }

        if let nextAcceptedMonotonicMs,
           nowMonotonicMs <= nextAcceptedMonotonicMs + targetFrameIntervalMs {
            self.nextAcceptedMonotonicMs = nextAcceptedMonotonicMs + targetFrameIntervalMs
        } else {
            self.nextAcceptedMonotonicMs = nowMonotonicMs + targetFrameIntervalMs
        }

        sequence += 1
        let currentSequence = sequence
        let captureTimeMs = Clock.wallTimeMs()

        statsMonitor.recordCapturedFrame()

        if currentSequence == 1 || currentSequence % Int64(max(config.logEveryFrames, 1)) == 0 {
            Logger.info("captured frame: seq=\(currentSequence) captureTimeMs=\(captureTimeMs)")
        }

        if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            if currentSequence == 1 || currentSequence % Int64(max(config.logEveryFrames, 1)) == 0 {
                Logger.info("capture sampleBuffer size: seq=\(currentSequence) \(CVPixelBufferGetWidth(imageBuffer))x\(CVPixelBufferGetHeight(imageBuffer))")
            }
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let presentationTimeNs = presentationTime.seconds.isFinite ? Int64(presentationTime.seconds * 1_000_000_000) : Int64(captureTimeMs * 1_000_000)
            let rawFrame = RawVideoFrame(
                pixelBuffer: imageBuffer,
                sequence: currentSequence,
                captureTimeMs: captureTimeMs,
                presentationTimeNs: presentationTimeNs,
                width: Int32(CVPixelBufferGetWidth(imageBuffer)),
                height: Int32(CVPixelBufferGetHeight(imageBuffer))
            )
            rawFrameHandler?(rawFrame)
        }

        encoder.encode(sampleBuffer: sampleBuffer, sequence: currentSequence, captureTimeMs: captureTimeMs)

        if let maxFrames = config.maxFrames, currentSequence >= maxFrames {
            stopHandler?()
        }
    }

    private func configureSession(device: AVCaptureDevice) throws {
        session.beginConfiguration()
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw SenderError.cannotCreateCaptureInput(error.localizedDescription)
        }

        guard session.canAddInput(input) else {
            throw SenderError.cannotAddCaptureInput
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: Int(config.width),
            kCVPixelBufferHeightKey as String: Int(config.height)
        ]
        Logger.info("AVCaptureVideoDataOutput videoSettings を設定しました: NV12 \(config.width)x\(config.height)")
        output.setSampleBufferDelegate(self, queue: captureQueue)

        guard session.canAddOutput(output) else {
            throw SenderError.cannotAddCaptureOutput
        }
        session.addOutput(output)

        if let connection = output.connection(with: .video) {
            connection.isEnabled = true
        }

        session.commitConfiguration()
        Logger.info("AVCaptureSession を構成しました: input=\(device.localizedName) pixelFormat=NV12")
    }
}
