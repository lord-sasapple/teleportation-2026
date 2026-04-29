import Foundation

struct FrameTimestampMessage: Codable, Sendable {
    let type: String
    let sequence: Int64
    let captureTimeMs: Int64
    let encodeStartTimeMs: Int64
    let encodeEndTimeMs: Int64
    let sendTimeMs: Int64

    init(sequence: Int64, captureTimeMs: Int64, encodeStartTimeMs: Int64, encodeEndTimeMs: Int64, sendTimeMs: Int64) {
        self.type = "frame-timestamp"
        self.sequence = sequence
        self.captureTimeMs = captureTimeMs
        self.encodeStartTimeMs = encodeStartTimeMs
        self.encodeEndTimeMs = encodeEndTimeMs
        self.sendTimeMs = sendTimeMs
    }

    func jsonString() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

struct FrameLatencyReportMessage: Codable, Sendable {
    let type: String
    let sequence: Int64
    let captureTimeMs: Int64
    let encodeEndTimeMs: Int64
    let receiverDataTimeMs: Int64
    let firstFrameSeenTimeMs: Int64
    let renderSubmitTimeMs: Int64
    let estimatedAppLatencyMs: Int64
}

