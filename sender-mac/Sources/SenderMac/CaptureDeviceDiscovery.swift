import AVFoundation
import CoreMedia
import Foundation

struct CaptureDeviceDiscovery {
    static func discoverVideoDevices() -> [AVCaptureDevice] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        )
        return session.devices
    }

    static func selectDevice(config: AppConfig) throws -> AVCaptureDevice {
        let devices = discoverVideoDevices()

        if let uniqueID = config.deviceUniqueId,
           let device = devices.first(where: { $0.uniqueID == uniqueID }) {
            return device
        }

        // --builtin-camera フラグが立っている場合は内蔵カメラを優先
        if config.useBuiltinCamera {
            if let builtinDevice = devices.first(where: { $0.deviceType == .builtInWideAngleCamera }) {
                Logger.info("内蔵カメラを使用します: \(builtinDevice.localizedName)")
                return builtinDevice
            }
            Logger.warn("--builtin-camera が指定されていますが内蔵カメラが見つかりません")
        }

        let hint = config.deviceNameHint.lowercased()
        if let device = devices.first(where: { $0.localizedName.lowercased().contains(hint) }) {
            return device
        }

        if let x5LikeDevice = devices.first(where: {
            let name = $0.localizedName.lowercased()
            return name.contains("x5") || name.contains("insta360")
        }) {
            return x5LikeDevice
        }

        guard let firstDevice = devices.first else {
            throw SenderError.noVideoDevice
        }

        Logger.warn("指定された X5 が見つからないため、最初の video device を使います: \(firstDevice.localizedName)")
        return firstDevice
    }

    static func printDevices() {
        let devices = discoverVideoDevices()

        if devices.isEmpty {
            Logger.warn("video device が見つかりませんでした")
            return
        }

        for device in devices {
            Logger.info("device: name=\(device.localizedName) uniqueID=\(device.uniqueID) type=\(device.deviceType.rawValue)")
            printFormats(for: device)
        }
    }

    static func configureFormat(device: AVCaptureDevice, config: AppConfig) throws {
        guard let selection = chooseFormat(device: device, config: config) else {
            throw SenderError.noMatchingFormat(deviceName: device.localizedName, width: config.width, height: config.height, fps: config.fps)
        }

        try device.lockForConfiguration()
        defer {
            device.unlockForConfiguration()
        }

        device.activeFormat = selection.format
        let frameDuration = CMTime(seconds: 1.0 / selection.fps, preferredTimescale: 60_000)
        device.activeVideoMinFrameDuration = frameDuration
        device.activeVideoMaxFrameDuration = frameDuration

        let dimensions = CMVideoFormatDescriptionGetDimensions(selection.format.formatDescription)
        if !selection.isExactMatch {
            Logger.warn("要求 format が見つからないため近い format を使います: requested=\(config.width)x\(config.height)@\(config.fps)fps actual=\(dimensions.width)x\(dimensions.height)@\(String(format: "%.2f", selection.fps))fps")
        }
        Logger.info("capture format を設定しました: \(dimensions.width)x\(dimensions.height) @ \(String(format: "%.2f", selection.fps))fps")
    }

    private static func chooseFormat(device: AVCaptureDevice, config: AppConfig) -> FormatSelection? {
        let targetFPS = Double(config.fps)

        let matches = device.formats.compactMap { format -> FormatSelection? in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard dimensions.width == config.width && dimensions.height == config.height else {
                return nil
            }

            guard let selectedFPS = supportedFPS(for: format, targetFPS: targetFPS) else {
                return nil
            }

            return FormatSelection(format: format, fps: selectedFPS, isExactMatch: true)
        }

        if let exact = matches.sorted(by: { lhs, rhs in
            abs(lhs.fps - targetFPS) < abs(rhs.fps - targetFPS)
        }).first {
            return exact
        }

        guard config.useBuiltinCamera else {
            return nil
        }

        return chooseClosestBuiltinFormat(device: device, targetWidth: config.width, targetHeight: config.height, targetFPS: config.fps)
    }

    private static func supportedFPS(for format: AVCaptureDevice.Format, targetFPS: Double) -> Double? {
        let tolerance = 0.5

        for range in format.videoSupportedFrameRateRanges {
            if range.minFrameRate - tolerance <= targetFPS && targetFPS <= range.maxFrameRate + tolerance {
                if range.minFrameRate <= targetFPS && targetFPS <= range.maxFrameRate {
                    return targetFPS
                }

                if abs(range.maxFrameRate - targetFPS) <= tolerance {
                    return range.maxFrameRate
                }

                if abs(range.minFrameRate - targetFPS) <= tolerance {
                    return range.minFrameRate
                }
            }
        }

        return nil
    }

    private static func chooseClosestBuiltinFormat(device: AVCaptureDevice, targetWidth: Int32, targetHeight: Int32, targetFPS: Int32) -> FormatSelection? {
        let candidates = device.formats.compactMap { format -> (format: AVCaptureDevice.Format, dimensions: CMVideoDimensions, fps: Int32, supportsTargetFPS: Bool)? in
            let ranges = format.videoSupportedFrameRateRanges
            guard let bestRange = ranges.max(by: { $0.maxFrameRate < $1.maxFrameRate }) else {
                return nil
            }
            let selectedTargetFPS = supportedFPS(for: format, targetFPS: Double(targetFPS))
            let supportsTargetFPS = selectedTargetFPS != nil
            let selectedFPS = selectedTargetFPS ?? max(1.0, bestRange.maxFrameRate)
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return (format, dimensions, selectedFPS, supportsTargetFPS)
        }

        let targetPixels = Int(targetWidth) * Int(targetHeight)
        let sorted = candidates.sorted { lhs, rhs in
            if lhs.supportsTargetFPS != rhs.supportsTargetFPS {
                return lhs.supportsTargetFPS && !rhs.supportsTargetFPS
            }

            let lhsPixels = Int(lhs.dimensions.width) * Int(lhs.dimensions.height)
            let rhsPixels = Int(rhs.dimensions.width) * Int(rhs.dimensions.height)
            let lhsScore = abs(lhsPixels - targetPixels)
            let rhsScore = abs(rhsPixels - targetPixels)
            if lhsScore != rhsScore {
                return lhsScore < rhsScore
            }
            return lhs.fps > rhs.fps
        }

        guard let best = sorted.first else {
            return nil
        }

        return FormatSelection(format: best.format, fps: best.fps, isExactMatch: false)
    }

    private static func printFormats(for device: AVCaptureDevice) {
        for format in device.formats {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let codec = CMFormatDescriptionGetMediaSubType(format.formatDescription).fourCCString
            let ranges = format.videoSupportedFrameRateRanges
                .map { "\(String(format: "%.0f", $0.minFrameRate))-\(String(format: "%.0f", $0.maxFrameRate))fps" }
                .joined(separator: ", ")

            Logger.info("  format: \(dimensions.width)x\(dimensions.height) codec=\(codec) fps=[\(ranges)]")
        }
    }
}

private struct FormatSelection {
    let format: AVCaptureDevice.Format
    let fps: Double
    let isExactMatch: Bool
}

private extension FourCharCode {
    var fourCCString: String {
        let scalars = [
            UnicodeScalar(UInt8((self >> 24) & 0xff)),
            UnicodeScalar(UInt8((self >> 16) & 0xff)),
            UnicodeScalar(UInt8((self >> 8) & 0xff)),
            UnicodeScalar(UInt8(self & 0xff))
        ]
        return String(String.UnicodeScalarView(scalars))
    }
}
