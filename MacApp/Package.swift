// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "TruNASApp",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "TruNASApp",
            path: "Sources/TruNASApp"
        )
    ]
)
