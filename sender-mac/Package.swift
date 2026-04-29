// swift-tools-version: 6.0

import Foundation
import PackageDescription

let webRTCFrameworkPath = "ThirdParty/WebRTC/WebRTC.xcframework"
let hasWebRTCFramework = FileManager.default.fileExists(atPath: webRTCFrameworkPath)
let webRTCProvider = ProcessInfo.processInfo.environment["WEBRTC_PROVIDER"] ?? "local"
let useLiveKitWebRTC = webRTCProvider == "livekit"

var targets: [Target] = []
var dependencies: [Package.Dependency] = []
var senderDependencies: [Target.Dependency] = []
var senderSwiftSettings: [SwiftSetting] = []

if useLiveKitWebRTC {
    dependencies.append(
        .package(
            url: "https://github.com/livekit/webrtc-xcframework.git",
            exact: "137.7151.03"
        )
    )
    senderDependencies.append(.product(name: "LiveKitWebRTC", package: "webrtc-xcframework"))
    senderSwiftSettings.append(.define("HAS_LIVEKIT_WEBRTC"))
} else if hasWebRTCFramework {
    targets.append(
        .binaryTarget(
            name: "WebRTC",
            path: webRTCFrameworkPath
        )
    )
    senderDependencies.append(.target(name: "WebRTC"))
    senderSwiftSettings.append(.define("HAS_WEBRTC"))
}

targets.append(
    .executableTarget(
        name: "SenderMac",
        dependencies: senderDependencies,
        path: "Sources/SenderMac",
        swiftSettings: senderSwiftSettings
    )
)

let package = Package(
    name: "SenderMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "sender-mac", targets: ["SenderMac"])
    ],
    dependencies: dependencies,
    targets: targets
)
