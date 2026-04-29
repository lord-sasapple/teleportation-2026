import Foundation

final class GlassToGlassTestMode: @unchecked Sendable {
    private var statsLock = NSLock()
    private var frameLatencies: [Int64] = []
    private var captureToRenderLatencies: [Int64] = []
    private var totalFrameTimestamps: Int64 = 0
    private var totalLatencyReports: Int64 = 0
    private var minLatencyMs: Int64 = Int64.max
    private var maxLatencyMs: Int64 = Int64.min
    private var testStartTime: Int64?
    private var enabled: Bool = false

    init(enabled: Bool = false) {
        self.enabled = enabled
        if enabled {
            testStartTime = Clock.wallTimeMs()
            Logger.info("===== application latency report 集計モードを有効にしました =====")
            Logger.info("正確な glass-to-glass latency は docs/latency-measurement.md の外部カメラ測定で確認してください")
        }
    }

    func recordFrameTimestamp(_ message: FrameTimestampMessage) {
        guard enabled else { return }
        
        statsLock.lock()
        defer { statsLock.unlock() }
        totalFrameTimestamps += 1
    }

    func recordLatencyReport(_ report: FrameLatencyReportMessage) {
        guard enabled else { return }
        
        statsLock.lock()
        defer { statsLock.unlock() }
        totalLatencyReports += 1
        
        let captureToRender = report.renderSubmitTimeMs - report.captureTimeMs
        let estimatedAppLatency = report.estimatedAppLatencyMs
        
        frameLatencies.append(estimatedAppLatency)
        captureToRenderLatencies.append(captureToRender)
        
        minLatencyMs = min(minLatencyMs, estimatedAppLatency)
        maxLatencyMs = max(maxLatencyMs, estimatedAppLatency)
        
        if totalLatencyReports % 30 == 0 {
            logLatencyStats()
        }
    }

    private func logLatencyStats() {
        guard !frameLatencies.isEmpty else {
            return
        }
        
        let avgLatency = frameLatencies.reduce(0, +) / Int64(frameLatencies.count)
        let sorted = frameLatencies.sorted()
        let medianLatency = frameLatencies.count % 2 == 0 ?
            (sorted[frameLatencies.count / 2 - 1] + sorted[frameLatencies.count / 2]) / 2 :
            sorted[frameLatencies.count / 2]
        
        Logger.info(String(
            format: "application latency report: avg=%ldms min=%ldms max=%ldms median=%ldms count=%ld",
            avgLatency, minLatencyMs, maxLatencyMs, medianLatency, totalLatencyReports
        ))
    }

    func printFinalStats() {
        guard enabled else { return }
        
        statsLock.lock()
        defer { statsLock.unlock() }
        
        Logger.info("===== application latency report 最終統計 =====")
        Logger.info(String(format: "frame timestamps sent: %ld", totalFrameTimestamps))
        Logger.info(String(format: "latency reports received: %ld", totalLatencyReports))
        
        guard !frameLatencies.isEmpty else {
            Logger.info("latency data がありません")
            Logger.info("=====================================")
            return
        }
        
        let avgLatency = frameLatencies.reduce(0, +) / Int64(frameLatencies.count)
        let sorted = frameLatencies.sorted()
        let medianLatency = frameLatencies.count % 2 == 0 ?
            (sorted[frameLatencies.count / 2 - 1] + sorted[frameLatencies.count / 2]) / 2 :
            sorted[frameLatencies.count / 2]
        
        let p95Latency = percentile(sorted, percentile: 0.95)
        let p99Latency = percentile(sorted, percentile: 0.99)
        
        Logger.info(String(format: "estimated app latency (ms):"))
        Logger.info(String(format: "  平均: %ldms", avgLatency))
        Logger.info(String(format: "  中央値: %ldms", medianLatency))
        Logger.info(String(format: "  最小: %ldms", minLatencyMs != Int64.max ? minLatencyMs : 0))
        Logger.info(String(format: "  最大: %ldms", maxLatencyMs != Int64.min ? maxLatencyMs : 0))
        Logger.info(String(format: "  P95: %ldms", p95Latency))
        Logger.info(String(format: "  P99: %ldms", p99Latency))
        
        if !captureToRenderLatencies.isEmpty {
            let avgCaptureToRender = captureToRenderLatencies.reduce(0, +) / Int64(captureToRenderLatencies.count)
            Logger.info(String(format: "capture-to-render latency (ms): 平均 %ldms", avgCaptureToRender))
        }
        
        if let testStartTime = testStartTime {
            let testDurationMs = Clock.wallTimeMs() - testStartTime
            Logger.info(String(format: "テスト実行時間: %ldms", testDurationMs))
        }
        
        Logger.info("=====================================")
    }

    func isEnabled() -> Bool {
        return enabled
    }

    private func percentile(_ sortedValues: [Int64], percentile: Double) -> Int64 {
        guard !sortedValues.isEmpty else {
            return 0
        }
        let bounded = min(max(percentile, 0), 1)
        let index = max(0, min(sortedValues.count - 1, Int(ceil(Double(sortedValues.count) * bounded)) - 1))
        return sortedValues[index]
    }
}
