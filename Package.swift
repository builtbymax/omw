// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "omw",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "OMWCore"),
        .executableTarget(
            name: "omw",
            dependencies: ["OMWCore"],
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        .testTarget(name: "OMWCoreTests", dependencies: ["OMWCore"]),
    ],
    swiftLanguageModes: [.v5]
)
