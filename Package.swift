// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "InputLock",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "InputLock",
            path: "Sources/InputLock",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("AppKit")
            ]
        )
    ]
)
