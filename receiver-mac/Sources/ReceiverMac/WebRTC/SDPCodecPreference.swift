import Foundation

enum SDPCodecPreference {
    static func preferVideoCodecs(in sdp: String, first preferredCodecs: [String]) -> String {
        var lines = sdp.split(whereSeparator: \ .isNewline).map(String.init)

        guard let mVideoIndex = lines.firstIndex(where: { $0.hasPrefix("m=video ") }) else {
            return sdp
        }

        let codecPayloads = extractCodecPayloads(from: lines)
        var preferredPayloads: [String] = []
        var fallbackPayloads: [String] = []

        for payload in parsePayloads(fromMLine: lines[mVideoIndex]) {
            if let codec = codecPayloads[payload] {
                if preferredCodecs.contains(where: { codec.uppercased().contains($0.uppercased()) }) {
                    preferredPayloads.append(payload)
                } else {
                    fallbackPayloads.append(payload)
                }
            } else {
                fallbackPayloads.append(payload)
            }
        }

        let ordered = preferredPayloads + fallbackPayloads
        guard !ordered.isEmpty else {
            return sdp
        }

        let prefix = lines[mVideoIndex].split(separator: " ").prefix(3).joined(separator: " ")
        lines[mVideoIndex] = "\(prefix) \(ordered.joined(separator: " "))"

        return lines.joined(separator: "\r\n")
    }

    private static func extractCodecPayloads(from lines: [String]) -> [String: String] {
        var map: [String: String] = [:]

        for line in lines where line.hasPrefix("a=rtpmap:") {
            let value = String(line.dropFirst("a=rtpmap:".count))
            let parts = value.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let payload = parts[0]
            let codec = parts[1]
            map[payload] = codec
        }

        return map
    }

    private static func parsePayloads(fromMLine line: String) -> [String] {
        let parts = line.split(separator: " ").map(String.init)
        guard parts.count > 3 else { return [] }
        return Array(parts.dropFirst(3))
    }
}
