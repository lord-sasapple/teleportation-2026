import Foundation

final class CodecStatsLogger: @unchecked Sendable {
    private var statsLock = NSLock()
    private var selectedCodec: String?
    private var codecNegotiationStartTime: Int64?
    private var sdpLines: [String] = []
    private var supportedCodecs: [String] = []
    private var negotiationComplete = false

    func logSupportedCodecs(_ codecs: [String]) {
        statsLock.lock()
        defer { statsLock.unlock() }
        supportedCodecs = codecs
        Logger.info("サポートされているコーデック: \(codecs.joined(separator: ", "))")
    }

    func logSdpOffer(_ sdp: String) {
        statsLock.lock()
        defer { statsLock.unlock() }
        codecNegotiationStartTime = Clock.wallTimeMs()
        sdpLines = extractCodecLines(from: sdp)
        Logger.info("offer SDP を作成しました: コーデック行数=\(sdpLines.count)")
        for line in sdpLines.prefix(5) {
            Logger.info("  \(line)")
        }
    }

    func logCodecPreference(preferred: [String], sdp: String) {
        statsLock.lock()
        defer { statsLock.unlock() }
        Logger.info("コーデック優先度の設定:")
        Logger.info("  希望: \(preferred.joined(separator: ", "))")
        Logger.info("  ペイロード: \(extractVideoPayloadMap(from: sdp))")
    }

    func logSdpAnswer(_ sdp: String) {
        statsLock.lock()
        defer { statsLock.unlock() }
        let answerCodecLines = extractCodecLines(from: sdp)
        Logger.info("answer SDP を受信しました: コーデック行数=\(answerCodecLines.count)")
        for line in answerCodecLines.prefix(3) {
            Logger.info("  \(line)")
        }

        if let selectedCodec = extractSelectedVideoCodec(from: sdp) {
            selectCodecLocked(selectedCodec)
        } else {
            Logger.warn("answer SDP から選択 codec を推定できませんでした")
        }
    }

    func selectCodec(_ codec: String) {
        statsLock.lock()
        defer { statsLock.unlock() }
        selectCodecLocked(codec)
    }

    private func selectCodecLocked(_ codec: String) {
        selectedCodec = codec
        let negotiationDuration = codecNegotiationStartTime.map { Clock.wallTimeMs() - $0 } ?? -1
        Logger.info("===== コーデック交渉完了 =====")
        Logger.info("選択されたコーデック: \(codec)")
        if negotiationDuration > 0 {
            Logger.info("交渉時間: \(negotiationDuration)ms")
        }
        Logger.info("============================")
        negotiationComplete = true
    }

    func getSelectedCodec() -> String? {
        statsLock.lock()
        defer { statsLock.unlock() }
        return selectedCodec
    }

    func getStats() -> CodecStatsSnapshot {
        statsLock.lock()
        defer { statsLock.unlock() }
        return CodecStatsSnapshot(
            selectedCodec: selectedCodec,
            supportedCodecs: supportedCodecs,
            sdpCodecLines: sdpLines,
            negotiationComplete: negotiationComplete
        )
    }
}

struct CodecStatsSnapshot: Sendable {
    let selectedCodec: String?
    let supportedCodecs: [String]
    let sdpCodecLines: [String]
    let negotiationComplete: Bool
}

private func extractCodecLines(from sdp: String) -> [String] {
    let lines = sdp.split(whereSeparator: \.isNewline).map(String.init)
    return lines.filter { line in
        (line.hasPrefix("a=rtpmap:") || line.hasPrefix("a=fmtp:")) &&
        (line.uppercased().contains("H265") || line.uppercased().contains("HEVC") || line.uppercased().contains("H264"))
    }
}

private func extractVideoPayloadMap(from sdp: String) -> [String: String] {
    var payloads: [String: String] = [:]
    for line in sdp.split(whereSeparator: \.isNewline).map(String.init) {
        guard line.hasPrefix("a=rtpmap:") else {
            continue
        }

        let rest = line.dropFirst("a=rtpmap:".count)
        let parts = rest.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            continue
        }

        let codec = parts[1].split(separator: "/", maxSplits: 1).first.map(String.init) ?? parts[1]
        if codec.uppercased().contains("H265") || codec.uppercased().contains("HEVC") || codec.uppercased().contains("H264") {
            payloads[parts[0]] = codec
        }
    }
    return payloads
}

private func extractSelectedVideoCodec(from sdp: String) -> String? {
    let lines = sdp.split(whereSeparator: \.isNewline).map(String.init)
    var videoPayloads: [String] = []

    for line in lines where line.hasPrefix("m=video ") {
        let parts = line.split(separator: " ").map(String.init)
        if parts.count > 3 {
            videoPayloads = Array(parts.dropFirst(3))
        }
        break
    }

    let payloadMap = extractVideoPayloadMap(from: sdp)
    for payload in videoPayloads {
        if let codec = payloadMap[payload] {
            return codec
        }
    }

    return payloadMap.values.first
}
