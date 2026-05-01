import AppKit
import CoreImage
import CoreVideo
import Foundation
import SceneKit

struct ViewerFrameUpdateResult: Sendable {
    let wasUpdated: Bool
    let detail: String
    let totalDurationMs: Int64
    let cgImageDurationMs: Int64
    let nsImageDurationMs: Int64
    let materialUpdateDurationMs: Int64

    static func skipped(reason: String) -> ViewerFrameUpdateResult {
        ViewerFrameUpdateResult(
            wasUpdated: false,
            detail: reason,
            totalDurationMs: 0,
            cgImageDurationMs: 0,
            nsImageDurationMs: 0,
            materialUpdateDurationMs: 0
        )
    }
}

@MainActor
final class Viewer360 {
    private var yaw: Double = 0
    private var pitch: Double = 0
    private let ciContext = CIContext()
    private var frameCount: Int64 = 0
    private var lastFrameUpdateMs: Int64 = 0
    private let minFrameUpdateIntervalMs: Int64 = 33

    private var window: NSWindow?
    private var sceneView: MouseLookSCNView?
    private var cameraNode: SCNNode?
    private var sphereMaterial: SCNMaterial?

    func start() {
        setupWindowIfNeeded()
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        Logger.info("360 viewer を開始しました")
    }

    func stop() {
        window?.orderOut(nil)
        Logger.info("360 viewer を停止しました")
    }

    func cameraPose() -> (yaw: Double, pitch: Double) {
        (yaw, pitch)
    }

    func showPreviewRendererView(_ rendererView: NSView) {
        setupWindowIfNeeded()

        guard let sceneView else {
            Logger.warn("preview renderer view を表示できません: sceneView がありません")
            return
        }

        if rendererView.superview !== sceneView {
            rendererView.removeFromSuperview()
            rendererView.translatesAutoresizingMaskIntoConstraints = false
            rendererView.wantsLayer = true
            rendererView.layer?.zPosition = 100
            sceneView.addSubview(rendererView)

            NSLayoutConstraint.activate([
                rendererView.leadingAnchor.constraint(equalTo: sceneView.leadingAnchor),
                rendererView.trailingAnchor.constraint(equalTo: sceneView.trailingAnchor),
                rendererView.topAnchor.constraint(equalTo: sceneView.topAnchor),
                rendererView.bottomAnchor.constraint(equalTo: sceneView.bottomAnchor)
            ])
            Logger.info("preview renderer view を viewer に埋め込みました")
        }

        window?.makeKeyAndOrderFront(nil)
    }

    @discardableResult
    func updateFrame(_ pixelBuffer: CVPixelBuffer) -> ViewerFrameUpdateResult {
        let startMs = Self.nowMs()
        if startMs - lastFrameUpdateMs < minFrameUpdateIntervalMs {
            return .skipped(reason: "viewer fps gate interval=\(startMs - lastFrameUpdateMs)ms")
        }
        lastFrameUpdateMs = startMs
        frameCount += 1

        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let cgStartMs = Self.nowMs()
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else {
            Logger.warn("receiver frame を CGImage に変換できません")
            return .skipped(reason: "CGImage conversion failed")
        }
        let cgEndMs = Self.nowMs()

        let nsStartMs = Self.nowMs()
        let nsImage = NSImage(
            cgImage: cgImage,
            size: NSSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        )
        let nsEndMs = Self.nowMs()

        let materialStartMs = Self.nowMs()
        sphereMaterial?.diffuse.contents = nsImage
        let materialEndMs = Self.nowMs()

        let result = ViewerFrameUpdateResult(
            wasUpdated: true,
            detail: "size=\(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer)) cgImage=\(cgEndMs - cgStartMs)ms nsImage=\(nsEndMs - nsStartMs)ms material=\(materialEndMs - materialStartMs)ms",
            totalDurationMs: materialEndMs - startMs,
            cgImageDurationMs: cgEndMs - cgStartMs,
            nsImageDurationMs: nsEndMs - nsStartMs,
            materialUpdateDurationMs: materialEndMs - materialStartMs
        )

        if frameCount == 1 || frameCount % 30 == 0 {
            Logger.info("viewer texture を更新しました: frames=\(frameCount) size=\(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer)) total=\(result.totalDurationMs)ms cgImage=\(result.cgImageDurationMs)ms nsImage=\(result.nsImageDurationMs)ms material=\(result.materialUpdateDurationMs)ms")
        }

        return result
    }

    private func setupWindowIfNeeded() {
        if window != nil {
            return
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let scene = SCNScene()

        let camera = SCNCamera()
        camera.fieldOfView = 90
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(cameraNode)
        self.cameraNode = cameraNode

        let sphere = SCNSphere(radius: 10)
        sphere.segmentCount = 192
        let material = SCNMaterial()
        material.isDoubleSided = true
        material.diffuse.contents = Self.placeholderGridImage(size: 2048)
        material.cullMode = .front
        sphere.firstMaterial = material
        sphereMaterial = material

        let sphereNode = SCNNode(geometry: sphere)
        sphereNode.scale = SCNVector3(-1, 1, 1)
        scene.rootNode.addChildNode(sphereNode)

        let frame = NSRect(x: 100, y: 100, width: 1280, height: 720)
        let view = MouseLookSCNView(frame: frame)
        view.scene = scene
        view.pointOfView = cameraNode
        view.backgroundColor = NSColor.black
        view.allowsCameraControl = false
        view.rendersContinuously = true
        view.preferredFramesPerSecond = 60
        view.onDrag = { [weak self] dx, dy in
            self?.onMouseDrag(deltaX: dx, deltaY: dy)
        }
        self.sceneView = view

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "receiver-mac 360 viewer"
        window.contentView = view
        window.makeFirstResponder(view)
        self.window = window

        updateCamera()
    }

    private func onMouseDrag(deltaX: Double, deltaY: Double) {
        yaw += deltaX * 0.005
        pitch += deltaY * 0.005
        pitch = max(-1.5, min(1.5, pitch))
        updateCamera()
    }

    private func updateCamera() {
        guard let cameraNode else { return }
        cameraNode.eulerAngles = SCNVector3(Float(pitch), Float(yaw), 0)
    }

    private static func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    private static func placeholderGridImage(size: Int) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size / 2))
        image.lockFocus()

        NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size / 2)).fill()

        NSColor(calibratedWhite: 0.22, alpha: 1).setStroke()
        for x in stride(from: 0, through: size, by: 64) {
            NSBezierPath.strokeLine(
                from: NSPoint(x: x, y: 0),
                to: NSPoint(x: x, y: size / 2)
            )
        }
        for y in stride(from: 0, through: size / 2, by: 64) {
            NSBezierPath.strokeLine(
                from: NSPoint(x: 0, y: y),
                to: NSPoint(x: size, y: y)
            )
        }

        let text = "receiver-mac 360 placeholder"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 28, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        text.draw(at: NSPoint(x: 40, y: 40), withAttributes: attrs)

        image.unlockFocus()
        return image
    }
}

final class MouseLookSCNView: SCNView {
    var onDrag: ((Double, Double) -> Void)?

    private var previousPoint: NSPoint?

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        previousPoint = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        let current = convert(event.locationInWindow, from: nil)
        guard let previousPoint else {
            self.previousPoint = current
            return
        }
        let dx = Double(current.x - previousPoint.x)
        let dy = Double(current.y - previousPoint.y)
        onDrag?(dx, dy)
        self.previousPoint = current
    }

    override func mouseUp(with event: NSEvent) {
        _ = event
        previousPoint = nil
    }
}
