import Foundation

struct AppConfig {
    var signalingURL: URL = URL(string: "wss://x5-webrtc-signaling.lord-sasapple.workers.dev")!
    var roomId: String = "x5-test-room"
    var preferredCodec: String = "hevc"
    var signalingOnly: Bool = false
    var duration: Int = 0
    var logEverySeconds: Int = 2
    var iceServers: [String] = ["stun:stun.l.google.com:19302"]

    static func parse(from arguments: [String]) throws -> AppConfig {
        var config = AppConfig()
        var index = 1

        while index < arguments.count {
            let value = arguments[index]
            switch value {
            case "--signaling-url":
                index += 1
                guard index < arguments.count, let url = URL(string: arguments[index]) else {
                    throw ReceiverError.invalidArgument("--signaling-url")
                }
                config.signalingURL = url
            case "--room":
                index += 1
                guard index < arguments.count else {
                    throw ReceiverError.invalidArgument("--room")
                }
                config.roomId = arguments[index]
            case "--codec":
                index += 1
                guard index < arguments.count else {
                    throw ReceiverError.invalidArgument("--codec")
                }
                config.preferredCodec = arguments[index].lowercased()
            case "--signaling-only":
                config.signalingOnly = true
            case "--duration":
                index += 1
                guard index < arguments.count, let seconds = Int(arguments[index]) else {
                    throw ReceiverError.invalidArgument("--duration")
                }
                config.duration = seconds
            case "--log-every-seconds":
                index += 1
                guard index < arguments.count, let seconds = Int(arguments[index]) else {
                    throw ReceiverError.invalidArgument("--log-every-seconds")
                }
                config.logEverySeconds = max(1, seconds)
            case "--ice-server":
                index += 1
                guard index < arguments.count else {
                    throw ReceiverError.invalidArgument("--ice-server")
                }
                if config.iceServers == ["stun:stun.l.google.com:19302"] {
                    config.iceServers.removeAll()
                }
                config.iceServers.append(arguments[index])
            case "-h", "--help":
                usage()
                exit(0)
            default:
                throw ReceiverError.unknownArgument(value)
            }
            index += 1
        }

        return config
    }

    static func usage() {
        print("receiver-mac")
        print("")
        print("Usage:")
        print("  swift run receiver-mac [options]")
        print("")
        print("Options:")
        print("  --signaling-url <wss://...>      signaling-worker URL")
        print("  --room <roomId>                  room id")
        print("  --codec <hevc|h264>              preferred codec (default: hevc)")
        print("  --signaling-only                 signaling test mode")
        print("  --duration <seconds>             auto stop after seconds (0 means run forever)")
        print("  --log-every-seconds <seconds>    stats log interval (default: 2)")
        print("  --ice-server <url>               ICE server URL. Repeatable. Default: stun:stun.l.google.com:19302")
        print("  -h, --help                       show help")
    }
}
