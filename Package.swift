// swift-tools-version: 6.0
import PackageDescription

// Command Line Tools only (no Xcode). Logic checks run inside the app: `Saku --selftest`.
let package = Package(
    name: "Saku",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Saku",
            path: "Sources/Saku",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
