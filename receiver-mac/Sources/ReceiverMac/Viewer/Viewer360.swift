import AppKit
import CoreImage
import CoreVideo
import Foundation
import SceneKit

@MainActor
final class Viewer360 {
    private var yaw: Double = 0
    private var pitch: Double = 0
    private var fieldOfView: Double = 90
    private let ciContext = CIContext()
    private var frameCount: Int64 = 0
    private var interactionCount: Int64 = 0
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
        _ = rendererView
        Logger.info("preview renderer view は 360 viewer では使用しません")
    }

    func updateFrame(_ pixelBuffer: CVPixelBuffer) {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        if nowMs - lastFrameUpdateMs < minFrameUpdateIntervalMs {
            return
        }
        lastFrameUpdateMs = nowMs
        frameCount += 1

        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else {
            Logger.warn("receiver frame を CGImage に変換できません")
            return
        }

        let nsImage = NSImage(
            cgImage: cgImage,
            size: NSSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        )
        sphereMaterial?.diffuse.contents = nsImage

        if frameCount == 1 || frameCount % 30 == 0 {
            Logger.info("viewer texture を更新しました: frames=\(frameCount) size=\(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer))")
        }
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
        view.onZoom = { [weak self] delta in
            self?.onZoom(delta: delta)
        }
        view.onReset = { [weak self] in
            self?.resetCamera()
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

        interactionCount += 1
        if interactionCount <= 3 {
            Logger.info(String(format: "viewer camera moved: yaw=%.3f pitch=%.3f", yaw, pitch))
        }
    }

    private func onZoom(delta: Double) {
        fieldOfView += delta * 0.25
        fieldOfView = max(45, min(110, fieldOfView))
        cameraNode?.camera?.fieldOfView = fieldOfView
    }

    private func resetCamera() {
        yaw = 0
        pitch = 0
        fieldOfView = 90
        cameraNode?.camera?.fieldOfView = fieldOfView
        updateCamera()
    }

    private func updateCamera() {
        guard let cameraNode else { return }
        cameraNode.eulerAngles = SCNVector3(Float(pitch), Float(yaw), 0)
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
    var onZoom: ((Double) -> Void)?
    var onReset: (() -> Void)?

    private var previousPoint: NSPoint?
    private var isMouseDragging = false

    override init(frame frameRect: NSRect, options: [String: Any]? = nil) {
        super.init(frame: frameRect, options: options)
        installGestureRecognizers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installGestureRecognizers()
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isMouseDragging = true
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
        isMouseDragging = false
        previousPoint = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        mouseDown(with: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        mouseDragged(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        mouseUp(with: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        mouseDown(with: event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        mouseDragged(with: event)
    }

    override func otherMouseUp(with event: NSEvent) {
        mouseUp(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        onZoom?(Double(event.scrollingDeltaY))
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 0:
            onDrag?(-24, 0)
        case 1:
            onDrag?(0, -24)
        case 2:
            onDrag?(24, 0)
        case 13:
            onDrag?(0, 24)
        case 15:
            onReset?()
        case 27:
            onZoom?(8)
        case 24:
            onZoom?(-8)
        case 123:
            onDrag?(-24, 0)
        case 124:
            onDrag?(24, 0)
        case 125:
            onDrag?(0, -24)
        case 126:
            onDrag?(0, 24)
        default:
            super.keyDown(with: event)
        }
    }

    private func installGestureRecognizers() {
        let pan = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)
    }

    @objc private func handlePan(_ recognizer: NSPanGestureRecognizer) {
        guard !isMouseDragging else { return }

        window?.makeFirstResponder(self)
        let translation = recognizer.translation(in: self)
        if translation != .zero {
            onDrag?(Double(translation.x), Double(translation.y))
            recognizer.setTranslation(.zero, in: self)
        }
    }
}
