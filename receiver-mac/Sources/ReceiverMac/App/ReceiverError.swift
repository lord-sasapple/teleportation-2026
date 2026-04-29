import Foundation

enum ReceiverError: LocalizedError {
    case unknownArgument(String)
    case invalidArgument(String)
    case signalingURLInvalid

    var errorDescription: String? {
        switch self {
        case .unknownArgument(let value):
            return "unknown argument: \(value)"
        case .invalidArgument(let flag):
            return "invalid value for \(flag)"
        case .signalingURLInvalid:
            return "invalid signaling url"
        }
    }
}
