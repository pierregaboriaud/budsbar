// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BudsBar",
    platforms: [.macOS(.v13)],
    targets: [
        // Protocol, CoreAudio helpers and the call-link recovery: no UI, no Bluetooth stack.
        .target(name: "BudsKit"),
        .executableTarget(
            name: "BudsBar",
            dependencies: ["BudsKit"],
            linkerSettings: [.linkedFramework("IOBluetooth")]
        ),
        .testTarget(name: "BudsKitTests", dependencies: ["BudsKit"]),
    ]
)
