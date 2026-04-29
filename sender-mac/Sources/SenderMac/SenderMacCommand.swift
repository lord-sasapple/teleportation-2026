import AVFoundation
import Darwin
import Foundation

@main
struct SenderMacCommand {
    static func main() {
        do {
            let config = try AppConfig.parse()
            try run(config: config)
        } catch ConfigError.helpRequested {
            print(AppConfig.usage())
        } catch let error as ConfigError {
            Logger.error(error.description)
            Foundation.exit(2)
        } catch let error as SenderError {
            Logger.error(error.description)
            Foundation.exit(1)
        } catch {
            Logger.error("予期しないエラーです: \(error.localizedDescription)")
            Foundation.exit(1)
        }
    }

    private static func run(config: AppConfig) throws {
        Logger.info("sender-mac を起動します: codec=\(config.codec.displayName) target=\(config.width)x\(config.height)@\(config.fps)fps bitrate=\(config.bitrate)bps")

        guard CameraAuthorization.request() else {
            throw SenderError.cameraPermissionDenied
        }

        if config.listDevices {
            CaptureDeviceDiscovery.printDevices()
            return
        }

        let device = try CaptureDeviceDiscovery.selectDevice(config: config)
        Logger.info("capture device を選択しました: name=\(device.localizedName) uniqueID=\(device.uniqueID)")
        try CaptureDeviceDiscovery.configureFormat(device: device, config: config)

        let senderSession = SenderSession(config: config)
        senderSession.start()

        let stopController = StopController()
        stopController.senderSession = senderSession

        let interruptSource = makeInterruptSource(stopController: stopController)
        let pipeline = try CapturePipeline(
            config: config,
            device: device,
            rawFrameHandler: { frame in
                senderSession.handleRawFrame(frame)
            },
            encodedFrameHandler: { frame in
                senderSession.handleEncodedFrame(frame)
            },
            stopHandler: {
                stopController.requestStop(reason: "max-frames に到達")
            }
        )
        stopController.pipeline = pipeline

        if let durationSeconds = config.durationSeconds {
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + durationSeconds) {
                Logger.info("duration に到達しました: \(durationSeconds)s")
                stopController.requestStop(reason: "duration に到達")
            }
        }

        pipeline.start()
        Logger.info("Ctrl-C で停止できます")
        stopController.waitUntilStopped()

        interruptSource.cancel()
        Logger.info("sender-mac を終了しました")
    }

    private static func makeInterruptSource(stopController: StopController) -> DispatchSourceSignal {
        signal(SIGINT, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global(qos: .userInitiated))
        source.setEventHandler {
            Logger.info("SIGINT を受信しました")
            stopController.requestStop(reason: "SIGINT")
        }
        source.resume()
        return source
    }
}
