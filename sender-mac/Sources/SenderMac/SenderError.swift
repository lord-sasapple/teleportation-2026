import Foundation

enum SenderError: Error, CustomStringConvertible {
    case noVideoDevice
    case noMatchingFormat(deviceName: String, width: Int32, height: Int32, fps: Int32)
    case cannotCreateCaptureInput(String)
    case cannotAddCaptureInput
    case cannotAddCaptureOutput
    case cannotCreateEncoder(OSStatus)
    case encoderPrepareFailed(OSStatus)
    case cameraPermissionDenied

    var description: String {
        switch self {
        case .noVideoDevice:
            "video device が見つかりません"
        case .noMatchingFormat(let deviceName, let width, let height, let fps):
            "\(deviceName) に \(width)x\(height) @ \(fps)fps の format が見つかりません。--list-devices で候補を確認してください"
        case .cannotCreateCaptureInput(let reason):
            "AVCaptureDeviceInput を作成できません: \(reason)"
        case .cannotAddCaptureInput:
            "AVCaptureSession に input を追加できません"
        case .cannotAddCaptureOutput:
            "AVCaptureSession に video output を追加できません"
        case .cannotCreateEncoder(let status):
            "VTCompressionSession を作成できません: OSStatus=\(status)"
        case .encoderPrepareFailed(let status):
            "VTCompressionSessionPrepareToEncodeFrames に失敗しました: OSStatus=\(status)"
        case .cameraPermissionDenied:
            "カメラ権限がありません。System Settings > Privacy & Security > Camera で Terminal または実行元アプリを許可してください"
        }
    }
}

