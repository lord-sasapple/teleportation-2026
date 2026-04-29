import Foundation

final class SignalingClient: @unchecked Sendable {
    private let baseURL: URL
    private let roomId: String
    private var task: URLSessionWebSocketTask?
    private lazy var session = URLSession(configuration: .default)

    var onMessage: (@Sendable (SignalingServerMessage) -> Void)?

    init(baseURL: URL, roomId: String) {
        self.baseURL = baseURL
        self.roomId = roomId
    }

    func connect() {
        let url = roomURL()
        Logger.info("signaling-worker に接続します: \(url.absoluteString)")

        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        receiveLoop()
        send(.join(roomId: roomId, role: .receiver))
        send(.ping)
    }

    func disconnect() {
        guard let task else { return }
        send(.leave)
        task.cancel(with: .normalClosure, reason: nil)
        self.task = nil
        Logger.info("signaling-worker から切断しました")
    }

    func sendAnswer(sdp: String) {
        send(.answer(sdp: sdp))
    }

    func sendIceCandidate(_ candidate: IceCandidatePayload) {
        send(.iceCandidate(candidate))
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    let decoded = SignalingMessageDecoder.decode(text: text)
                    self.onMessage?(decoded)
                case .data(let data):
                    Logger.info("signaling 受信(binary): \(data.count) bytes")
                @unknown default:
                    Logger.warn("未知の WebSocket message を受信しました")
                }
                self.receiveLoop()
            case .failure(let error):
                Logger.warn("signaling receive error: \(error.localizedDescription)")
            }
        }
    }

    private func send(_ message: SignalingClientMessage) {
        guard let task else { return }

        do {
            let data = try message.jsonData()
            guard let text = String(data: data, encoding: .utf8) else {
                Logger.warn("signaling JSON を UTF-8 文字列に変換できません")
                return
            }

            Logger.info("signaling 送信: \(message.logType)")
            task.send(.string(text)) { error in
                if let error {
                    Logger.warn("signaling 送信に失敗しました: \(error.localizedDescription)")
                }
            }
        } catch {
            Logger.warn("signaling JSON encode に失敗しました: \(error.localizedDescription)")
        }
    }

    private func roomURL() -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) ?? URLComponents()

        if components.scheme == "http" {
            components.scheme = "ws"
        } else if components.scheme == "https" {
            components.scheme = "wss"
        }

        components.path = "/room/\(roomId)"
        components.queryItems = [URLQueryItem(name: "role", value: "receiver")]

        return components.url ?? baseURL
    }
}
