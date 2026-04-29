import CoreMedia
import Foundation
import Network

final class PionFrameSocketClient: @unchecked Sendable {
    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port
    private let queue = DispatchQueue(label: "telepresence.sender.pion-frame-socket")
    private var connection: NWConnection?
    private var sentFrames: Int64 = 0

    init(address: String) throws {
        let parts = address.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let parsedPort = UInt16(parts[1]), let nwPort = NWEndpoint.Port(rawValue: parsedPort) else {
            throw SenderError.runtime("invalid pion frame socket address: \(address)")
        }
        host = NWEndpoint.Host(parts[0])
        port = nwPort
    }

    func start() {
        let connection = NWConnection(host: host, port: port, using: .tcp)
        self.connection = connection

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                Logger.info("Pion frame socket connected: \(self.host):\(self.port)")
            case .failed(let error):
                Logger.warn("Pion frame socket failed: \(error)")
            case .cancelled:
                Logger.info("Pion frame socket cancelled")
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    func stop() {
        connection?.cancel()
        connection = nil
    }

    func send(frame: EncodedVideoFrame) {
        guard frame.log.codec == .hevc else {
            return
        }

        guard let data = Self.makeAnnexBAccessUnit(from: frame.sampleBuffer) else {
            if frame.log.sequence == 1 || frame.log.sequence % 30 == 0 {
                Logger.warn("HEVC AnnexB 変換に失敗しました: seq=\(frame.log.sequence)")
            }
            return
        }

        var length = UInt32(data.count).bigEndian
        let header = Data(bytes: &length, count: 4)
        let packet = header + data

        connection?.send(content: packet, completion: .contentProcessed { error in
            if let error {
                Logger.warn("Pion frame socket send failed: \(error)")
            }
        })

        sentFrames += 1
        if sentFrames == 1 || sentFrames % 30 == 0 {
            Logger.info("Pion frame socket sent: frames=\(sentFrames) seq=\(frame.log.sequence) bytes=\(data.count) keyframe=\(frame.log.isKeyframe)")
        }
    }

    private static func makeAnnexBAccessUnit(from sampleBuffer: CMSampleBuffer) -> Data? {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return nil
        }

        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )

        guard status == noErr, let dataPointer, totalLength > 0 else {
            return nil
        }

        var output = Data()

        if sampleBuffer.isKeyframeForPionBridge {
            appendHEVCParameterSets(from: sampleBuffer, to: &output)
        }

        var offset = 0
        while offset + 4 <= totalLength {
            let b0 = UInt8(bitPattern: dataPointer[offset])
            let b1 = UInt8(bitPattern: dataPointer[offset + 1])
            let b2 = UInt8(bitPattern: dataPointer[offset + 2])
            let b3 = UInt8(bitPattern: dataPointer[offset + 3])
            let nalLength = Int(UInt32(b0) << 24 | UInt32(b1) << 16 | UInt32(b2) << 8 | UInt32(b3))
            offset += 4

            guard nalLength > 0, offset + nalLength <= totalLength else {
                return nil
            }

            output.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
            output.append(UnsafeBufferPointer(start: UnsafePointer<UInt8>(OpaquePointer(dataPointer + offset)), count: nalLength))
            offset += nalLength
        }

        return output.isEmpty ? nil : output
    }

    private static func appendHEVCParameterSets(from sampleBuffer: CMSampleBuffer, to output: inout Data) {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            return
        }

        var parameterSetCount = 0
        let countStatus = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
            formatDescription,
            parameterSetIndex: 0,
            parameterSetPointerOut: nil,
            parameterSetSizeOut: nil,
            parameterSetCountOut: &parameterSetCount,
            nalUnitHeaderLengthOut: nil
        )

        guard countStatus == noErr, parameterSetCount > 0 else {
            return
        }

        for index in 0..<parameterSetCount {
            var parameterSetPointer: UnsafePointer<UInt8>?
            var parameterSetSize = 0

            let status = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
                formatDescription,
                parameterSetIndex: index,
                parameterSetPointerOut: &parameterSetPointer,
                parameterSetSizeOut: &parameterSetSize,
                parameterSetCountOut: nil,
                nalUnitHeaderLengthOut: nil
            )

            guard status == noErr, let parameterSetPointer, parameterSetSize > 0 else {
                continue
            }

            output.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
            output.append(parameterSetPointer, count: parameterSetSize)
        }
    }
}

private extension CMSampleBuffer {
    var isKeyframeForPionBridge: Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(self, createIfNecessary: false) as? [[CFString: Any]],
              let first = attachments.first else {
            return false
        }

        let notSync = first[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
        return !notSync
    }
}
