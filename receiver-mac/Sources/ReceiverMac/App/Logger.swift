import Foundation

enum LogLevel: String {
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"
}

enum Logger {
    static var mirror: (@Sendable (LogLevel, String) -> Void)?
    private static let mirrorLock = NSLock()
    private static var isMirroring = false

    static func info(_ message: String) {
        write(.info, message)
    }

    static func warn(_ message: String) {
        write(.warn, message)
    }

    static func error(_ message: String) {
        write(.error, message)
    }

    private static func write(_ level: LogLevel, _ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        print("[\(timestamp)] [\(level.rawValue)] \(message)")

        mirrorLock.lock()
        if isMirroring {
            mirrorLock.unlock()
            return
        }
        isMirroring = true
        let mirror = mirror
        mirrorLock.unlock()

        mirror?(level, message)

        mirrorLock.lock()
        isMirroring = false
        mirrorLock.unlock()
    }
}
