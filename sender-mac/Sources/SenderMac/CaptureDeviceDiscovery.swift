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
        guard let format = chooseFormat(device: device, width: config.width, height: config.height, fps: config.fps) else {
            throw SenderError.noMatchingFormat(deviceName: device.localizedName, width: config.width, height: config.height, fps: config.fps)
        }

        try device.lockForConfiguration()
        defer {
            device.unlockForConfiguration()
        }

        device.activeFormat = format
        let frameDuration = CMTime(value: 1, timescale: config.fps)
        device.activeVideoMinFrameDuration = frameDuration
        device.activeVideoMaxFrameDuration = frameDuration

        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        Logger.info("capture format を設定しました: \(dimensions.width)x\(dimensions.height) @ \(config.fps)fps")
    }

    private static func chooseFormat(device: AVCaptureDevice, width: Int32, height: Int32, fps: Int32) -> AVCaptureDevice.Format? {
        let matches = device.formats.filter { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let supportsResolution = dimensions.width == width && dimensions.height == height
            let supportsFPS = format.videoSupportedFrameRateRanges.contains { range in
                range.minFrameRate <= Double(fps) && range.maxFrameRate >= Double(fps)
            }
            return supportsResolution && supportsFPS
        }

        return matches.sorted { lhs, rhs in
            let lhsMaxFPS = lhs.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
            let rhsMaxFPS = rhs.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
            return lhsMaxFPS < rhsMaxFPS
        }.first
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
