import Foundation

enum LogLevel: String {
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"
}

enum Logger {
    private static let mirrorState = LoggerMirrorState()

    static func setMirror(_ mirror: (@Sendable (LogLevel, String) -> Void)?) {
        mirrorState.set(mirror)
    }

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

        mirrorState.emit(level: level, message: message)
    }
}

private final class LoggerMirrorState: @unchecked Sendable {
    private let lock = NSLock()
    private var mirror: (@Sendable (LogLevel, String) -> Void)?
    private var isEmitting = false

    func set(_ mirror: (@Sendable (LogLevel, String) -> Void)?) {
        lock.lock()
        self.mirror = mirror
        lock.unlock()
    }

    func emit(level: LogLevel, message: String) {
        lock.lock()
        if isEmitting {
            lock.unlock()
            return
        }
        isEmitting = true
        let mirror = mirror
        lock.unlock()

        mirror?(level, message)

        lock.lock()
        isEmitting = false
        lock.unlock()
    }
}
