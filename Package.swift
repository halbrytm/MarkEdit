// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MarkEdit",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "MarkEdit", path: "Sources/MarkEdit")
    ]
)
