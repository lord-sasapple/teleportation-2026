// swift-tools-version: 6.0

import Foundation
import PackageDescription

let webRTCFrameworkPath = "ThirdParty/WebRTC/WebRTC.xcframework"
let hasWebRTCFramework = FileManager.default.fileExists(atPath: webRTCFrameworkPath)

var targets: [Target] = []
var senderDependencies: [Target.Dependency] = []
var senderSwiftSettings: [SwiftSetting] = []

if hasWebRTCFramework {
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
    targets: targets
)
