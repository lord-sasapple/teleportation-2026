import Foundation
import LiveKit

print("===== LiveKit Swift SDK H265 probe =====")

let allCodecs = VideoCodec.all.map { $0.name }
let backupCodecs = VideoCodec.allBackup.map { $0.name }

print("VideoCodec.all: \(allCodecs.joined(separator: ", "))")
print("VideoCodec.allBackup: \(backupCodecs.joined(separator: ", "))")

let fromName = VideoCodec.from(name: "h265")
let fromMime = VideoCodec.from(mimeType: "video/h265")

print("VideoCodec.from(name: h265): \(fromName?.description ?? "nil")")
print("VideoCodec.from(mimeType: video/h265): \(fromMime?.description ?? "nil")")

let publishOptions = VideoPublishOptions(
    encoding: VideoEncoding(maxBitrate: 30_000_000, maxFps: 30),
    simulcast: false,
    preferredCodec: .h265,
    preferredBackupCodec: .h264,
    degradationPreference: .maintainResolution
)

let roomOptions = RoomOptions(
    defaultVideoPublishOptions: publishOptions,
    adaptiveStream: false,
    dynacast: false
)

print("VideoPublishOptions.preferredCodec: \(publishOptions.preferredCodec?.description ?? "nil")")
print("VideoPublishOptions.preferredBackupCodec: \(publishOptions.preferredBackupCodec?.description ?? "nil")")
print("VideoPublishOptions.simulcast: \(publishOptions.simulcast)")
print("VideoPublishOptions.degradationPreference: \(publishOptions.degradationPreference)")
print("RoomOptions.defaultVideoPublishOptions.preferredCodec: \(roomOptions.defaultVideoPublishOptions.preferredCodec?.description ?? "nil")")

if allCodecs.contains("h265"), fromName != nil, fromMime != nil, publishOptions.preferredCodec == .h265 {
    print("RESULT: LiveKit Swift SDK layer exposes H265")
} else {
    print("RESULT: LiveKit Swift SDK layer does NOT expose H265")
}

print("========================================")
