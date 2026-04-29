import Foundation

final class FrameEncodeContext {
    let sequence: Int64
    let captureTimeMs: Int64
    let encodeStartTimeMs: Int64
    let presentationTimeMs: Double
    let encodeStartMonotonicMs: Double

    init(sequence: Int64, captureTimeMs: Int64, encodeStartTimeMs: Int64, presentationTimeMs: Double, encodeStartMonotonicMs: Double) {
        self.sequence = sequence
        self.captureTimeMs = captureTimeMs
        self.encodeStartTimeMs = encodeStartTimeMs
        self.presentationTimeMs = presentationTimeMs
        self.encodeStartMonotonicMs = encodeStartMonotonicMs
    }
}

struct EncodedFrameLog: Sendable {
    let sequence: Int64
    let captureTimeMs: Int64
    let encodeStartTimeMs: Int64
    let encodeEndTimeMs: Int64
    let presentationTimeMs: Double
    let encodeDurationMs: Double
    let sizeBytes: Int
    let isKeyframe: Bool
    let codec: SenderCodec
}
