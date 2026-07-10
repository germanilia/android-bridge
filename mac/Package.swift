// swift-tools-version:5.9
import PackageDescription

// macOS app (SwiftUI) + shared core. The Device-Link Protocol is a path dependency on ../protocol/swift.
// Tests use XCTest + SwiftCheck (Xcode installed). `MacCheck` remains as an Xcode-free smoke runner.
// A runnable .app is assembled from the `AndroidBridge` executable via scripts/make-macos-app.sh.

let package = Package(
    name: "AndroidBridgeMac",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "BridgeCore", targets: ["BridgeCore"]),
        .executable(name: "AndroidBridge", targets: ["BridgeApp"]),
        .executable(name: "MacCheck", targets: ["MacCheck"]),
        .executable(name: "HfpProbe", targets: ["HfpProbe"]),
    ],
    dependencies: [
        .package(path: "../protocol/swift"),
        .package(url: "https://github.com/typelift/SwiftCheck.git", from: "0.12.0"),
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "BridgeCore",
            dependencies: [
                .product(name: "DeviceLinkProtocol", package: "swift"),
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "Crypto", package: "swift-crypto"),
            ]
        ),
        .executableTarget(
            name: "BridgeApp",
            dependencies: ["BridgeCore"]
        ),
        .executableTarget(
            name: "MacCheck",
            dependencies: ["BridgeCore", .product(name: "DeviceLinkProtocol", package: "swift")]
        ),
        // Increment 2 (HFP audio spike): hardware probe that tries to make the Mac the
        // Bluetooth Hands-Free (HF) endpoint for a paired phone via IOBluetoothHandsFreeDevice,
        // proving whether cellular call audio can route into CoreAudio on the target Mac.
        .executableTarget(name: "HfpProbe"),
        .testTarget(
            name: "BridgeCoreTests",
            dependencies: [
                "BridgeCore",
                .product(name: "DeviceLinkProtocol", package: "swift"),
                .product(name: "SwiftCheck", package: "SwiftCheck"),
            ]
        ),
    ]
)
