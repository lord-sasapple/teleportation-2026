import AVFoundation
import Foundation

enum CameraAuthorization {
    static func request() -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            let semaphore = DispatchSemaphore(value: 0)
            let result = AuthorizationResult()
            AVCaptureDevice.requestAccess(for: .video) { allowed in
                result.set(allowed)
                semaphore.signal()
            }
            semaphore.wait()
            return result.get()
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}

private final class AuthorizationResult: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set(_ newValue: Bool) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> Bool {
        lock.lock()
        defer {
            lock.unlock()
        }
        return value
    }
}
