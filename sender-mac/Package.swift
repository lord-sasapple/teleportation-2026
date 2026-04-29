// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SenderMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "sender-mac", targets: ["SenderMac"])
    ],
    targets: [
        .executableTarget(
            name: "SenderMac",
            path: "Sources/SenderMac"
        )
    ]
)

