import AVFoundation
import CoreMedia
import Foundation
import VideoToolbox

final class VideoEncoder: @unchecked Sendable {
    private let config: AppConfig
    private let width: Int32
    private let height: Int32
    private var session: VTCompressionSession?
    private var encodedFrames: Int64 = 0
    var encodedFrameHandler: (@Sendable (EncodedVideoFrame) -> Void)?

    init(config: AppConfig, width: Int32, height: Int32) throws {
        self.config = config
        self.width = width
        self.height = height
        try createSession(requireHardware: true)
    }

    deinit {
        finish()
    }

    func encode(sampleBuffer: CMSampleBuffer, sequence: Int64, captureTimeMs: Int64) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let session else {
            Logger.warn("encode 対象の CVPixelBuffer または encoder session がありません")
            return
        }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let presentationTimeMs = presentationTime.seconds.isFinite ? presentationTime.seconds * 1000.0 : 0
        let context = FrameEncodeContext(
            sequence: sequence,
            captureTimeMs: captureTimeMs,
            encodeStartTimeMs: Clock.wallTimeMs(),
            presentationTimeMs: presentationTimeMs,
            encodeStartMonotonicMs: Clock.monotonicMs()
        )

        let contextRef = Unmanaged.passRetained(context)
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: imageBuffer,
            presentationTimeStamp: presentationTime,
            duration: .invalid,
            frameProperties: nil,
            sourceFrameRefcon: contextRef.toOpaque(),
            infoFlagsOut: nil
        )

        if status != noErr {
            contextRef.release()
            Logger.warn("encode enqueue に失敗しました: sequence=\(sequence) OSStatus=\(status)")
        }
    }

    func finish() {
        guard let session else {
            return
        }

        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        VTCompressionSessionInvalidate(session)
        self.session = nil
    }

    private func createSession(requireHardware: Bool) throws {
        let codecType = config.codec.cmCodecType
        let encoderSpecification: CFDictionary = [
            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true,
            kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: requireHardware
        ] as CFDictionary

        var createdSession: VTCompressionSession?
        let createStatus = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: codecType,
            encoderSpecification: encoderSpecification,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: videoEncoderOutputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &createdSession
        )

        guard createStatus == noErr, let createdSession else {
            throw SenderError.cannotCreateEncoder(createStatus)
        }

        session = createdSession
        configureProperties(on: createdSession)

        let prepareStatus = VTCompressionSessionPrepareToEncodeFrames(createdSession)
        guard prepareStatus == noErr else {
            throw SenderError.encoderPrepareFailed(prepareStatus)
        }

        Logger.info("encoder を作成しました: codec=\(config.codec.displayName) \(width)x\(height) bitrate=\(config.bitrate)bps")
        logHardwareEncoderState(createdSession)
    }

    private func configureProperties(on session: VTCompressionSession) {
        setProperty(kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue, session: session)
        setProperty(kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse, session: session)
        setProperty(kVTCompressionPropertyKey_AverageBitRate, value: config.bitrate as CFTypeRef, session: session)
        setProperty(kVTCompressionPropertyKey_ExpectedFrameRate, value: config.fps as CFTypeRef, session: session)
        setProperty(kVTCompressionPropertyKey_MaxKeyFrameInterval, value: config.fps * Int32(config.keyframeIntervalSeconds) as CFTypeRef, session: session)
        setProperty(kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: config.keyframeIntervalSeconds as CFTypeRef, session: session)

        switch config.codec {
        case .hevc:
            setProperty(kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_HEVC_Main_AutoLevel, session: session)
        case .h264:
            setProperty(kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_AutoLevel, session: session)
        }
    }

    private func setProperty(_ key: CFString, value: CFTypeRef, session: VTCompressionSession) {
        let status = VTSessionSetProperty(session, key: key, value: value)
        if status != noErr {
            Logger.warn("encoder property 設定に失敗しました: key=\(key) OSStatus=\(status)")
        }
    }

    private func logHardwareEncoderState(_ session: VTCompressionSession) {
        var copiedValue: Unmanaged<CFTypeRef>?
        let status = withUnsafeMutablePointer(to: &copiedValue) { pointer in
            VTSessionCopyProperty(
                session,
                key: kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder,
                allocator: kCFAllocatorDefault,
                valueOut: pointer
            )
        }

        guard status == noErr else {
            Logger.warn("hardware encoder 状態を取得できません: OSStatus=\(status)")
            return
        }

        let value = copiedValue?.takeRetainedValue()
        let usingHardware = (value as? Bool) ?? false
        if usingHardware {
            Logger.info("VideoToolbox hardware encoder を使用中です")
        } else {
            Logger.warn("software encoder に落ちている可能性があります")
        }
    }

    fileprivate func handleEncodedFrame(status: OSStatus, sampleBuffer: CMSampleBuffer?, context: FrameEncodeContext?) {
        guard status == noErr else {
            Logger.warn("encode callback error: OSStatus=\(status) sequence=\(context?.sequence ?? -1)")
            return
        }

        guard let sampleBuffer, let context else {
            Logger.warn("encode callback に sampleBuffer または context がありません")
            return
        }

        encodedFrames += 1
        let encodeEndTimeMs = Clock.wallTimeMs()
        let encodeDurationMs = Clock.monotonicMs() - context.encodeStartMonotonicMs
        let sizeBytes = CMSampleBufferGetTotalSampleSize(sampleBuffer)
        let log = EncodedFrameLog(
            sequence: context.sequence,
            captureTimeMs: context.captureTimeMs,
            encodeStartTimeMs: context.encodeStartTimeMs,
            encodeEndTimeMs: encodeEndTimeMs,
            presentationTimeMs: context.presentationTimeMs,
            encodeDurationMs: encodeDurationMs,
            sizeBytes: sizeBytes,
            isKeyframe: sampleBuffer.isKeyframe,
            codec: config.codec
        )

        if log.sequence == 1 || log.sequence % Int64(max(config.logEveryFrames, 1)) == 0 || log.isKeyframe {
            Logger.info(
                "encoded frame: seq=\(log.sequence) codec=\(log.codec.displayName) size=\(log.sizeBytes)B keyframe=\(log.isKeyframe) encodeMs=\(String(format: "%.2f", log.encodeDurationMs)) captureTimeMs=\(log.captureTimeMs) encodeEndTimeMs=\(log.encodeEndTimeMs)"
            )
        }

        encodedFrameHandler?(EncodedVideoFrame(sampleBuffer: sampleBuffer, log: log))
    }
}

private let videoEncoderOutputCallback: VTCompressionOutputCallback = { outputCallbackRefCon, sourceFrameRefCon, status, _, sampleBuffer in
    guard let outputCallbackRefCon else {
        return
    }

    let encoder = Unmanaged<VideoEncoder>.fromOpaque(outputCallbackRefCon).takeUnretainedValue()
    let context = sourceFrameRefCon.map {
        Unmanaged<FrameEncodeContext>.fromOpaque($0).takeRetainedValue()
    }

    encoder.handleEncodedFrame(status: status, sampleBuffer: sampleBuffer, context: context)
}

private extension SenderCodec {
    var cmCodecType: CMVideoCodecType {
        switch self {
        case .hevc:
            kCMVideoCodecType_HEVC
        case .h264:
            kCMVideoCodecType_H264
        }
    }
}

private extension CMSampleBuffer {
    var isKeyframe: Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(self, createIfNecessary: false) as? [[CFString: Any]],
              let first = attachments.first else {
            return false
        }

        let notSync = first[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
        return !notSync
    }
}
