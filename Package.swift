// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Vox",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Vox",
            path: "Sources/Vox",
            // Real-time audio + C event-tap APIs play nicer under the Swift 5
            // concurrency model. This is a personal tool, not a library.
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
