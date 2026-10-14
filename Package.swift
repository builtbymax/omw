// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "omw",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(name: "OMWCore"),
        .executableTarget(
            name: "omw",
            dependencies: ["OMWCore", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [
                .linkedFramework("Carbon"),
                // scripts/bundle.sh copies Sparkle.framework into omw.app/Contents/Frameworks.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        // The `omw` command-line tool. scripts/bundle.sh puts it into omw.app/Contents/Helpers/omw.
        .executableTarget(name: "omw-cli", dependencies: ["OMWCore"]),
        .testTarget(name: "OMWCoreTests", dependencies: ["OMWCore"]),
    ],
    swiftLanguageModes: [.v5]
)
