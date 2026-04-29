import AVFoundation
import CoreVideo
import Foundation

final class CapturePipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let config: AppConfig
    private let session = AVCaptureSession()
    private let captureQueue = DispatchQueue(label: "telepresence.sender.capture")
    private let encoder: VideoEncoder
    private var sequence: Int64 = 0
    private var isRunning = false
    private var stopHandler: (@Sendable () -> Void)?

    init(
        config: AppConfig,
        device: AVCaptureDevice,
        encodedFrameHandler: (@Sendable (EncodedVideoFrame) -> Void)? = nil,
        stopHandler: (@Sendable () -> Void)? = nil
    ) throws {
        self.config = config
        self.stopHandler = stopHandler

        let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        encoder = try VideoEncoder(config: config, width: dimensions.width, height: dimensions.height)
        encoder.encodedFrameHandler = encodedFrameHandler

        super.init()

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
        Logger.info("capture session を停止しました")
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        sequence += 1
        let currentSequence = sequence
        let captureTimeMs = Clock.wallTimeMs()

        if currentSequence == 1 || currentSequence % Int64(max(config.logEveryFrames, 1)) == 0 {
            Logger.info("captured frame: seq=\(currentSequence) captureTimeMs=\(captureTimeMs)")
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
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]
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
