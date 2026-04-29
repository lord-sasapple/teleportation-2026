import Foundation

struct FrameTimestampMessage: Codable, Sendable {
    let type: String
    let sequence: Int64
    let captureTimeMs: Int64
    let encodeStartTimeMs: Int64
    let encodeEndTimeMs: Int64
    let sendTimeMs: Int64
}

