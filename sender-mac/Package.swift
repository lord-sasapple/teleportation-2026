// swift-tools-version: 6.0

import Foundation
import PackageDescription

let webRTCFrameworkPath = "ThirdParty/WebRTC/WebRTC.xcframework"
let hasWebRTCFramework = FileManager.default.fileExists(atPath: webRTCFrameworkPath)
let webRTCProvider = ProcessInfo.processInfo.environment["WEBRTC_PROVIDER"] ?? "local"
let useLiveKitWebRTC = webRTCProvider == "livekit"
let useLiveKitSDK = webRTCProvider == "livekit-sdk"
let useStaselWebRTC = webRTCProvider == "stasel"

var products: [Product] = []
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
} else if useLiveKitSDK {
    dependencies.append(
        .package(
            url: "https://github.com/livekit/client-sdk-swift.git",
            branch: "main"
        )
    )

    targets.append(
        .executableTarget(
            name: "LiveKitSDKProbe",
            dependencies: [
                .product(name: "LiveKit", package: "client-sdk-swift")
            ],
            path: "Sources/LiveKitSDKProbe"
        )
    )

    products.append(
        .executable(name: "livekit-sdk-probe", targets: ["LiveKitSDKProbe"])
    )
} else if useStaselWebRTC {
    dependencies.append(
        .package(
            url: "https://github.com/stasel/WebRTC.git",
            branch: "latest"
        )
    )

    targets.append(
        .executableTarget(
            name: "StaselWebRTCProbe",
            dependencies: [
                .product(name: "WebRTC", package: "WebRTC")
            ],
            path: "Sources/StaselWebRTCProbe"
        )
    )

    products.append(
        .executable(name: "stasel-webrtc-probe", targets: ["StaselWebRTCProbe"])
    )
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

products.append(
    .executable(name: "sender-mac", targets: ["SenderMac"])
)

let package = Package(
    name: "SenderMac",
    platforms: [
        .macOS(.v14)
    ],
    products: products,
    dependencies: dependencies,
    targets: targets
)
