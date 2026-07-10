// swift-tools-version:5.9
import PackageDescription

// Property/example tests run via XCTest + SwiftCheck (the NFR-specified PBT framework), available now
// that Xcode is installed. The dependency-free `ProtocolCheck` executable is kept as a lightweight,
// Xcode-free smoke runner (`swift run ProtocolCheck`).

let package = Package(
    name: "DeviceLinkProtocol",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "DeviceLinkProtocol", targets: ["DeviceLinkProtocol"]),
        .executable(name: "ProtocolCheck", targets: ["ProtocolCheck"]),
    ],
    dependencies: [
        .package(url: "https://github.com/typelift/SwiftCheck.git", from: "0.12.0"),
    ],
    targets: [
        .target(name: "DeviceLinkProtocol"),
        .executableTarget(name: "ProtocolCheck", dependencies: ["DeviceLinkProtocol"]),
        .testTarget(
            name: "DeviceLinkProtocolTests",
            dependencies: ["DeviceLinkProtocol", .product(name: "SwiftCheck", package: "SwiftCheck")]
        ),
    ]
)
