import Foundation

enum SenderCodec: String {
    case hevc
    case h264

    var displayName: String {
        switch self {
        case .hevc:
            "HEVC/H.265"
        case .h264:
            "H.264"
        }
    }
}

struct AppConfig {
    var deviceNameHint: String = "Insta360 X5"
    var deviceUniqueId: String?
    var useBuiltinCamera: Bool = false
    var width: Int32 = 2880
    var height: Int32 = 1440
    var fps: Int32 = 30
    var codec: SenderCodec = .hevc
    var bitrate: Int = 18_000_000
    var keyframeIntervalSeconds: Int = 2
    var logEveryFrames: Int = 30
    var maxFrames: Int?
    var durationSeconds: Double?
    var listDevices: Bool = false
    var requestCameraPermission: Bool = false
    var cameraPermissionStatus: Bool = false
    var signalingOnly: Bool = false
    var glassToGlassTest: Bool = false
    var signalingBaseURL: URL?
    var roomId: String?
    var iceServers: [String] = ["stun:stun.l.google.com:19302"]
    var pionFrameSocket: String?
    var requiredAspectRatio: AspectRatio?

    static func parse(arguments: [String] = CommandLine.arguments) throws -> AppConfig {
        var config = AppConfig()
        var index = 1

        func value(after option: String) throws -> String {
            guard index + 1 < arguments.count else {
                throw ConfigError.missingValue(option)
            }
            index += 1
            return arguments[index]
        }

        while index < arguments.count {
            let arg = arguments[index]
            switch arg {
            case "--device-name":
                config.deviceNameHint = try value(after: arg)
            case "--device-id":
                config.deviceUniqueId = try value(after: arg)
            case "--width":
                config.width = try Int32(Self.parseInt(try value(after: arg), option: arg))
            case "--height":
                config.height = try Int32(Self.parseInt(try value(after: arg), option: arg))
            case "--require-aspect-ratio":
                config.requiredAspectRatio = try AspectRatio.parse(try value(after: arg), option: arg)
            case "--fps":
                config.fps = try Int32(Self.parseInt(try value(after: arg), option: arg))
            case "--codec":
                let rawValue = try value(after: arg).lowercased()
                guard let codec = SenderCodec(rawValue: rawValue) else {
                    throw ConfigError.invalidValue(arg, "hevc または h264 を指定してください")
                }
                config.codec = codec
            case "--bitrate":
                config.bitrate = try Self.parseInt(try value(after: arg), option: arg)
            case "--keyframe-interval":
                config.keyframeIntervalSeconds = try Self.parseInt(try value(after: arg), option: arg)
            case "--log-every":
                config.logEveryFrames = try Self.parseInt(try value(after: arg), option: arg)
            case "--max-frames":
                config.maxFrames = try Self.parseInt(try value(after: arg), option: arg)
            case "--duration":
                config.durationSeconds = try Self.parseDouble(try value(after: arg), option: arg)
            case "--list-devices":
                config.listDevices = true
            case "--request-camera-permission":
                config.requestCameraPermission = true
            case "--camera-permission-status":
                config.cameraPermissionStatus = true
            case "--signaling-only":
                config.signalingOnly = true
            case "--latency-report-test", "--glass-to-glass-test":
                config.glassToGlassTest = true
            case "--builtin-camera":
                config.useBuiltinCamera = true
            case "--signaling-url":
                let rawURL = try value(after: arg)
                guard let url = URL(string: rawURL) else {
                    throw ConfigError.invalidValue(arg, "URL として解釈できません")
                }
                config.signalingBaseURL = url
            case "--room":
                config.roomId = try value(after: arg)
            case "--ice-server":
                let server = try value(after: arg)
                if config.iceServers == ["stun:stun.l.google.com:19302"] {
                    config.iceServers.removeAll()
                }
                config.iceServers.append(server)
            case "--pion-frame-socket":
                config.pionFrameSocket = try value(after: arg)
            case "--help", "-h":
                throw ConfigError.helpRequested
            default:
                throw ConfigError.unknownOption(arg)
            }

            index += 1
        }

        return config
    }

    static func usage() -> String {
        """
        sender-mac

        Usage:
          swift run sender-mac [options]

        Options:
          --list-devices                 利用可能なカメラと format を表示して終了
          --request-camera-permission    SenderMac.app としてカメラ許可ダイアログを出す
          --camera-permission-status     現在のカメラ権限状態を表示して終了
          --device-name <name>           device localizedName の部分一致。既定: Insta360 X5
          --device-id <uniqueID>         device uniqueID を直接指定
          --builtin-camera               内蔵カメラを優先的に使用 (X5 なし時のテスト用)
          --width <px>                   既定: 2880
          --height <px>                  既定: 1440
          --require-aspect-ratio <w:h>   capture format の縦横比を要求。X5 360 は 2:1
          --fps <fps>                    既定: 30
          --codec <hevc|h264>            既定: hevc
          --bitrate <bps>                既定: 18000000
          --keyframe-interval <seconds>  既定: 2
          --log-every <frames>           既定: 30
          --max-frames <count>           指定フレーム数で停止
          --duration <seconds>           指定秒数で停止
          --signaling-only               カメラを使わず signaling / WebRTC 初期化だけ起動
          --latency-report-test          DataChannel latency report 集計を有効化
          --glass-to-glass-test          --latency-report-test の互換 alias
          --signaling-url <wss://...>    signaling-worker の base URL
          --room <roomId>                signaling-worker roomId
          --ice-server <url>             ICE server URL。複数指定可。既定: stun:stun.l.google.com:19302
          --pion-frame-socket <host:port> HEVC encoded frames をGo/PionへTCP送信する

        Examples:
          swift run sender-mac --list-devices
          swift run sender-mac --request-camera-permission
          swift run sender-mac --builtin-camera --codec hevc --duration 10
          swift run sender-mac --builtin-camera --codec h264 --duration 10
          swift run sender-mac --codec hevc --duration 10
          swift run sender-mac --codec h264 --bitrate 16000000 --max-frames 300
          swift run sender-mac --signaling-only --signaling-url wss://example.workers.dev --room smoke --duration 5
          swift run sender-mac --latency-report-test --signaling-url wss://example.workers.dev --room latency-test --duration 30
        """
    }

    private static func parseInt(_ rawValue: String, option: String) throws -> Int {
        guard let value = Int(rawValue) else {
            throw ConfigError.invalidValue(option, "整数として解釈できません: \(rawValue)")
        }
        return value
    }

    private static func parseDouble(_ rawValue: String, option: String) throws -> Double {
        guard let value = Double(rawValue) else {
            throw ConfigError.invalidValue(option, "数値として解釈できません: \(rawValue)")
        }
        return value
    }
}

struct AspectRatio {
    let width: Int32
    let height: Int32

    var label: String {
        "\(width):\(height)"
    }

    func matches(width actualWidth: Int32, height actualHeight: Int32) -> Bool {
        Int64(actualWidth) * Int64(height) == Int64(actualHeight) * Int64(width)
    }

    static func parse(_ rawValue: String, option: String) throws -> AspectRatio {
        let parts = rawValue.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let width = Int32(parts[0]),
              let height = Int32(parts[1]),
              width > 0,
              height > 0 else {
            throw ConfigError.invalidValue(option, "w:h 形式で指定してください。例: 2:1")
        }
        return AspectRatio(width: width, height: height)
    }
}

enum ConfigError: Error, CustomStringConvertible {
    case helpRequested
    case unknownOption(String)
    case missingValue(String)
    case invalidValue(String, String)

    var description: String {
        switch self {
        case .helpRequested:
            AppConfig.usage()
        case .unknownOption(let option):
            "不明なオプションです: \(option)\n\n\(AppConfig.usage())"
        case .missingValue(let option):
            "値が必要です: \(option)\n\n\(AppConfig.usage())"
        case .invalidValue(let option, let reason):
            "不正な値です: \(option): \(reason)\n\n\(AppConfig.usage())"
        }
    }
}
