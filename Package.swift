// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Offloadly",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Offloadly",
            path: "Sources/Offloadly",
            swiftSettings: [
                // Stay in Swift 5 language mode to avoid strict-concurrency
                // friction in the SwiftUI/AppKit glue code.
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
