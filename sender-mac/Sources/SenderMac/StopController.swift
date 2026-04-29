import Foundation

final class StopController: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var stopped = false

    var pipeline: CapturePipeline?
    var senderSession: SenderSession?

    func requestStop(reason: String) {
        lock.lock()
        if stopped {
            lock.unlock()
            return
        }
        stopped = true
        let pipeline = pipeline
        let senderSession = senderSession
        lock.unlock()

        Logger.info("停止要求を受け取りました: \(reason)")
        DispatchQueue.global(qos: .userInitiated).async { [semaphore] in
            pipeline?.stop()
            senderSession?.stop()
            semaphore.signal()
        }
    }

    func waitUntilStopped() {
        semaphore.wait()
    }
}
