import Foundation

enum Clock {
    static func wallTimeMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    static func monotonicMs() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000.0
    }
}

