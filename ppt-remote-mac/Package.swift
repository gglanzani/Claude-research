// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PPTRemote",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "PPTRemote",
            path: "Sources/PPTRemote",
            resources: [
                .copy("Resources/index.html"),
                .copy("Resources/Scripts"),
            ]
        ),
    ]
)
