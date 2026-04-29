// swift-tools-version: 6.0

import Foundation
import PackageDescription

let webRTCProvider = ProcessInfo.processInfo.environment["WEBRTC_PROVIDER"] ?? "local"
let useLiveKitWebRTC = webRTCProvider == "livekit"

var dependencies: [Package.Dependency] = []
var receiverDependencies: [Target.Dependency] = ["CWebRTCShim"]
var receiverSwiftSettings: [SwiftSetting] = []

if useLiveKitWebRTC {
    dependencies.append(
        .package(
            url: "https://github.com/livekit/webrtc-xcframework.git",
            exact: "144.7559.04"
        )
    )
    receiverDependencies.append(.product(name: "LiveKitWebRTC", package: "webrtc-xcframework"))
    receiverSwiftSettings.append(.define("HAS_LIVEKIT_WEBRTC"))
}

let package = Package(
    name: "receiver-mac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "receiver-mac", targets: ["ReceiverMac"]),
    ],
    dependencies: dependencies,
    targets: [
        .target(
            name: "CWebRTCShim",
            path: "Sources/CWebRTCShim",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "ReceiverMac",
            dependencies: receiverDependencies,
            path: "Sources/ReceiverMac",
            resources: [],
            swiftSettings: receiverSwiftSettings
        ),
    ]
)
