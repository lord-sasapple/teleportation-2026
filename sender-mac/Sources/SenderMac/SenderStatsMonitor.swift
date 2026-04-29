import Foundation

final class SenderStatsMonitor: @unchecked Sendable {
    private let logEveryFrames: Int
    private let codec: SenderCodec

    private var frameLock = NSLock()
    private var capturedFrames: Int64 = 0
    private var encodedFrames: Int64 = 0
    private var sentFrames: Int64 = 0

    private var totalCaptureDurationMs: Double = 0
    private var totalEncodeDurationMs: Double = 0
    private var totalEncodedSizeBytes: Int64 = 0
    private var totalKeyframes: Int64 = 0
    private var encodeLatencyCount: Int64 = 0
    private var encodeLatencyMeanMs: Double = 0
    private var encodeLatencyM2: Double = 0

    private var minEncodeDurationMs: Double = Double.infinity
    private var maxEncodeDurationMs: Double = -Double.infinity

    init(codec: SenderCodec, logEveryFrames: Int = 30) {
        self.codec = codec
        self.logEveryFrames = logEveryFrames
    }

    func recordCapturedFrame() {
        frameLock.lock()
        defer { frameLock.unlock() }
        capturedFrames += 1
    }

    func recordEncodedFrame(_ frame: EncodedFrameLog) {
        let shouldLog: Bool
        let stats: SenderStatsSnapshot?

        frameLock.lock()
        encodedFrames += 1
        totalEncodedSizeBytes += Int64(frame.sizeBytes)
        totalEncodeDurationMs += frame.encodeDurationMs
        if frame.isKeyframe {
            totalKeyframes += 1
        }

        minEncodeDurationMs = min(minEncodeDurationMs, frame.encodeDurationMs)
        maxEncodeDurationMs = max(maxEncodeDurationMs, frame.encodeDurationMs)

        if frame.encodeStartTimeMs != 0 {
            let encodeLatencyMs = Double(frame.encodeEndTimeMs - frame.captureTimeMs)
            encodeLatencyCount += 1
            let delta = encodeLatencyMs - encodeLatencyMeanMs
            encodeLatencyMeanMs += delta / Double(encodeLatencyCount)
            encodeLatencyM2 += delta * (encodeLatencyMs - encodeLatencyMeanMs)
        }

        shouldLog = encodedFrames % Int64(max(logEveryFrames, 1)) == 0
        stats = shouldLog ? snapshotLocked() : nil
        frameLock.unlock()

        if let stats {
            logStats(stats)
        }
    }

    func recordSentFrame(_ sequence: Int64) {
        _ = sequence
        frameLock.lock()
        defer { frameLock.unlock() }
        sentFrames += 1
    }

    func getStats() -> SenderStatsSnapshot {
        frameLock.lock()
        defer { frameLock.unlock() }

        return snapshotLocked()
    }

    private func snapshotLocked() -> SenderStatsSnapshot {
        let avgEncodeDurationMs = encodedFrames > 0 ? totalEncodeDurationMs / Double(encodedFrames) : 0
        let avgEncodedSizeBytes = encodedFrames > 0 ? totalEncodedSizeBytes / encodedFrames : 0
        let keyframeRatio = encodedFrames > 0 ? Double(totalKeyframes) / Double(encodedFrames) * 100 : 0
        let encodeLatencyStdDev = encodeLatencyCount > 1 ? sqrt(encodeLatencyM2 / Double(encodeLatencyCount - 1)) : 0

        return SenderStatsSnapshot(
            capturedFrames: capturedFrames,
            encodedFrames: encodedFrames,
            sentFrames: sentFrames,
            codec: codec,
            avgEncodeDurationMs: avgEncodeDurationMs,
            minEncodeDurationMs: minEncodeDurationMs != Double.infinity ? minEncodeDurationMs : 0,
            maxEncodeDurationMs: maxEncodeDurationMs != -Double.infinity ? maxEncodeDurationMs : 0,
            avgEncodedSizeBytes: avgEncodedSizeBytes,
            totalEncodedMB: Double(totalEncodedSizeBytes) / (1024 * 1024),
            keyframeRatio: keyframeRatio,
            encodeLatencyStdDevMs: encodeLatencyStdDev
        )
    }

    private func logStats(_ stats: SenderStatsSnapshot) {
        let statsLog = String(
            format: "encode stats: codec=%@ frames=%lld avg-encode=%.2fms min=%.2fms max=%.2fms avg-size=%.0fKB keyframe=%.1f%% capture-to-encode-stddev=%.2fms",
            codec.displayName,
            encodedFrames,
            stats.avgEncodeDurationMs,
            stats.minEncodeDurationMs,
            stats.maxEncodeDurationMs,
            Double(stats.avgEncodedSizeBytes) / 1024,
            stats.keyframeRatio,
            stats.encodeLatencyStdDevMs
        )
        Logger.info(statsLog)
    }

    func printFinalStats() {
        let stats = getStats()
        Logger.info("===== sender-mac 最終統計 =====")
        Logger.info("codec: \(stats.codec.displayName)")
        Logger.info("frames captured: \(stats.capturedFrames)")
        Logger.info("frames encoded: \(stats.encodedFrames)")
        Logger.info("frames sent: \(stats.sentFrames)")
        Logger.info(String(format: "encode avg: %.2fms (min: %.2fms, max: %.2fms)", stats.avgEncodeDurationMs, stats.minEncodeDurationMs, stats.maxEncodeDurationMs))
        Logger.info(String(format: "capture-to-encode stddev: %.2fms", stats.encodeLatencyStdDevMs))
        Logger.info(String(format: "avg encoded size: %.0f KB", Double(stats.avgEncodedSizeBytes) / 1024))
        Logger.info(String(format: "total encoded: %.2f MB", stats.totalEncodedMB))
        Logger.info(String(format: "keyframe ratio: %.1f%%", stats.keyframeRatio))
        Logger.info("=================================")
    }
}

struct SenderStatsSnapshot: Sendable {
    let capturedFrames: Int64
    let encodedFrames: Int64
    let sentFrames: Int64
    let codec: SenderCodec
    let avgEncodeDurationMs: Double
    let minEncodeDurationMs: Double
    let maxEncodeDurationMs: Double
    let avgEncodedSizeBytes: Int64
    let totalEncodedMB: Double
    let keyframeRatio: Double
    let encodeLatencyStdDevMs: Double
}
