import Foundation

enum SDPCodecPreference {
    static func preferVideoCodecs(in sdp: String, first preferredNames: [String]) -> String {
        let lineSeparator = sdp.contains("\r\n") ? "\r\n" : "\n"
        var lines = sdp.components(separatedBy: lineSeparator)

        guard let mediaIndex = lines.firstIndex(where: { $0.hasPrefix("m=video ") }) else {
            return sdp
        }

        let payloadNameById = parsePayloadNames(lines: lines)
        var mediaParts = lines[mediaIndex].split(separator: " ").map(String.init)
        guard mediaParts.count > 3 else {
            return sdp
        }

        let prefix = Array(mediaParts.prefix(3))
        let payloads = Array(mediaParts.dropFirst(3))
        let sortedPayloads = payloads.sorted { lhs, rhs in
            priority(for: payloadNameById[lhs], preferredNames: preferredNames) < priority(for: payloadNameById[rhs], preferredNames: preferredNames)
        }

        mediaParts = prefix + sortedPayloads
        lines[mediaIndex] = mediaParts.joined(separator: " ")
        return lines.joined(separator: lineSeparator)
    }


    static func addVideoBandwidthHints(
        to sdp: String,
        startKbps: Int,
        minKbps: Int,
        maxKbps: Int
    ) -> String {
        let lineSeparator = sdp.contains("\r\n") ? "\r\n" : "\n"
        var lines = sdp.components(separatedBy: lineSeparator)

        guard let mediaIndex = lines.firstIndex(where: { $0.hasPrefix("m=video ") }) else {
            return sdp
        }

        // Remove old video-level bandwidth hints immediately after m=video.
        var removeIndexes: [Int] = []
        var i = mediaIndex + 1
        while i < lines.count {
            let line = lines[i]
            if line.hasPrefix("m=") {
                break
            }
            if line.hasPrefix("b=AS:") || line.hasPrefix("b=TIAS:") {
                removeIndexes.append(i)
            }
            i += 1
        }
        for index in removeIndexes.reversed() {
            lines.remove(at: index)
        }

        lines.insert("b=TIAS:\(maxKbps * 1000)", at: mediaIndex + 1)
        lines.insert("b=AS:\(maxKbps)", at: mediaIndex + 1)

        let payloadNameById = parsePayloadNames(lines: lines)
        let h264Payloads = payloadNameById
            .filter { $0.value.uppercased().contains("H264") }
            .map(\.key)

        for payload in h264Payloads {
            if let fmtpIndex = lines.firstIndex(where: { $0.hasPrefix("a=fmtp:\(payload) ") }) {
                var line = lines[fmtpIndex]
                let params = [
                    "x-google-start-bitrate=\(startKbps)",
                    "x-google-min-bitrate=\(minKbps)",
                    "x-google-max-bitrate=\(maxKbps)"
                ]

                for param in params {
                    let key = param.split(separator: "=").first.map(String.init) ?? param
                    if !line.contains(key) {
                        line += ";\(param)"
                    }
                }

                lines[fmtpIndex] = line
            } else if let rtpmapIndex = lines.firstIndex(where: { $0.hasPrefix("a=rtpmap:\(payload) ") }) {
                lines.insert(
                    "a=fmtp:\(payload) x-google-start-bitrate=\(startKbps);x-google-min-bitrate=\(minKbps);x-google-max-bitrate=\(maxKbps)",
                    at: rtpmapIndex + 1
                )
            }
        }

        return lines.joined(separator: lineSeparator)
    }


    private static func parsePayloadNames(lines: [String]) -> [String: String] {
        var result: [String: String] = [:]

        for line in lines where line.hasPrefix("a=rtpmap:") {
            let suffix = line.dropFirst("a=rtpmap:".count)
            let parts = suffix.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                continue
            }

            let payloadId = parts[0]
            let codecName = parts[1].split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
            result[payloadId] = codecName.uppercased()
        }

        return result
    }

    private static func priority(for codecName: String?, preferredNames: [String]) -> Int {
        guard let codecName else {
            return preferredNames.count + 1
        }

        let uppercased = codecName.uppercased()
        for (index, preferredName) in preferredNames.enumerated() where uppercased.contains(preferredName.uppercased()) {
            return index
        }

        return preferredNames.count
    }
}

