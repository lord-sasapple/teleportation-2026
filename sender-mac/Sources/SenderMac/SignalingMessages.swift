import Foundation

enum SignalingRole: String, Codable {
    case sender
    case receiver
}

struct IceCandidatePayload: Codable, Sendable {
    let candidate: String
    let sdpMid: String?
    let sdpMLineIndex: Int?
}

enum SignalingServerMessage: Sendable {
    case joined(roomId: String, role: SignalingRole)
    case peerJoined(role: SignalingRole)
    case offer(sdp: String)
    case answer(sdp: String)
    case iceCandidate(IceCandidatePayload)
    case peerLeft(role: SignalingRole)
    case pong
    case error(message: String)
    case latencySync(sequence: Int64, senderTimeMs: Int64)
    case latencyEcho(sequence: Int64, senderTimeMs: Int64, receiverTimeMs: Int64)
    case unknown(type: String)
}

enum SignalingClientMessage: Sendable {
    case join(roomId: String, role: SignalingRole)
    case offer(sdp: String)
    case answer(sdp: String)
    case iceCandidate(IceCandidatePayload)
    case leave
    case ping
    case latencySync(sequence: Int64, senderTimeMs: Int64)
    case latencyEcho(sequence: Int64, senderTimeMs: Int64, receiverTimeMs: Int64)

    var logType: String {
        switch self {
        case .join:
            "join"
        case .offer:
            "offer"
        case .answer:
            "answer"
        case .iceCandidate:
            "ice-candidate"
        case .leave:
            "leave"
        case .ping:
            "ping"
        case .latencySync:
            "latency-sync"
        case .latencyEcho:
            "latency-echo"
        }
    }

    func jsonData() throws -> Data {
        try JSONSerialization.data(withJSONObject: jsonObject(), options: [])
    }

    private func jsonObject() -> [String: Any] {
        switch self {
        case .join(let roomId, let role):
            return ["type": "join", "roomId": roomId, "role": role.rawValue]
        case .offer(let sdp):
            return ["type": "offer", "sdp": sdp]
        case .answer(let sdp):
            return ["type": "answer", "sdp": sdp]
        case .iceCandidate(let candidate):
            var candidateObject: [String: Any] = [
                "candidate": candidate.candidate
            ]
            if let sdpMid = candidate.sdpMid {
                candidateObject["sdpMid"] = sdpMid
            }
            if let sdpMLineIndex = candidate.sdpMLineIndex {
                candidateObject["sdpMLineIndex"] = sdpMLineIndex
            }
            return [
                "type": "ice-candidate",
                "candidate": candidateObject
            ]
        case .leave:
            return ["type": "leave"]
        case .ping:
            return ["type": "ping"]
        case .latencySync(let sequence, let senderTimeMs):
            return ["type": "latency-sync", "sequence": sequence, "senderTimeMs": senderTimeMs]
        case .latencyEcho(let sequence, let senderTimeMs, let receiverTimeMs):
            return [
                "type": "latency-echo",
                "sequence": sequence,
                "senderTimeMs": senderTimeMs,
                "receiverTimeMs": receiverTimeMs
            ]
        }
    }
}

enum SignalingMessageDecoder {
    static func decode(text: String) -> SignalingServerMessage {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else {
            return .unknown(type: "invalid-json")
        }

        switch type {
        case "joined":
            return .joined(
                roomId: object["roomId"] as? String ?? "",
                role: SignalingRole(rawValue: object["role"] as? String ?? "") ?? .sender
            )
        case "peer-joined":
            return .peerJoined(role: SignalingRole(rawValue: object["role"] as? String ?? "") ?? .receiver)
        case "offer":
            return .offer(sdp: object["sdp"] as? String ?? "")
        case "answer":
            return .answer(sdp: object["sdp"] as? String ?? "")
        case "ice-candidate":
            return .iceCandidate(parseCandidate(object["candidate"]))
        case "peer-left":
            return .peerLeft(role: SignalingRole(rawValue: object["role"] as? String ?? "") ?? .receiver)
        case "pong":
            return .pong
        case "error":
            return .error(message: object["message"] as? String ?? "unknown error")
        case "latency-sync":
            return .latencySync(
                sequence: int64(object["sequence"]),
                senderTimeMs: int64(object["senderTimeMs"])
            )
        case "latency-echo":
            return .latencyEcho(
                sequence: int64(object["sequence"]),
                senderTimeMs: int64(object["senderTimeMs"]),
                receiverTimeMs: int64(object["receiverTimeMs"])
            )
        default:
            return .unknown(type: type)
        }
    }

    private static func parseCandidate(_ value: Any?) -> IceCandidatePayload {
        guard let object = value as? [String: Any] else {
            return IceCandidatePayload(candidate: "", sdpMid: nil, sdpMLineIndex: nil)
        }

        return IceCandidatePayload(
            candidate: object["candidate"] as? String ?? "",
            sdpMid: object["sdpMid"] as? String,
            sdpMLineIndex: object["sdpMLineIndex"] as? Int
        )
    }

    private static func int64(_ value: Any?) -> Int64 {
        if let int = value as? Int {
            return Int64(int)
        }
        if let int64 = value as? Int64 {
            return int64
        }
        if let double = value as? Double {
            return Int64(double)
        }
        return 0
    }
}
