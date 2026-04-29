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
    case unknown(type: String)
}

enum SignalingClientMessage: Sendable {
    case join(roomId: String, role: SignalingRole)
    case answer(sdp: String)
    case iceCandidate(IceCandidatePayload)
    case receiverLog(level: String, message: String, timestampMs: Int64)
    case leave
    case ping

    var logType: String {
        switch self {
        case .join: return "join"
        case .answer: return "answer"
        case .iceCandidate: return "ice-candidate"
        case .receiverLog: return "receiver-log"
        case .leave: return "leave"
        case .ping: return "ping"
        }
    }

    func jsonData() throws -> Data {
        try JSONSerialization.data(withJSONObject: jsonObject(), options: [])
    }

    private func jsonObject() -> [String: Any] {
        switch self {
        case .join(let roomId, let role):
            return ["type": "join", "roomId": roomId, "role": role.rawValue]
        case .answer(let sdp):
            return ["type": "answer", "sdp": sdp]
        case .iceCandidate(let candidate):
            var candidateObject: [String: Any] = ["candidate": candidate.candidate]
            if let sdpMid = candidate.sdpMid {
                candidateObject["sdpMid"] = sdpMid
            }
            if let sdpMLineIndex = candidate.sdpMLineIndex {
                candidateObject["sdpMLineIndex"] = sdpMLineIndex
            }
            return ["type": "ice-candidate", "candidate": candidateObject]
        case .receiverLog(let level, let message, let timestampMs):
            return [
                "type": "receiver-log",
                "level": level,
                "message": message,
                "timestampMs": timestampMs
            ]
        case .leave:
            return ["type": "leave"]
        case .ping:
            return ["type": "ping"]
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
                role: SignalingRole(rawValue: object["role"] as? String ?? "") ?? .receiver
            )
        case "peer-joined":
            return .peerJoined(role: SignalingRole(rawValue: object["role"] as? String ?? "") ?? .sender)
        case "offer":
            return .offer(sdp: object["sdp"] as? String ?? "")
        case "answer":
            return .answer(sdp: object["sdp"] as? String ?? "")
        case "ice-candidate":
            return .iceCandidate(parseCandidate(object["candidate"]))
        case "peer-left":
            return .peerLeft(role: SignalingRole(rawValue: object["role"] as? String ?? "") ?? .sender)
        case "pong":
            return .pong
        case "error":
            return .error(message: object["message"] as? String ?? "unknown error")
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
}
