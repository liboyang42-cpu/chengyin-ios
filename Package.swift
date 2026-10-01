// swift-tools-version: 5.9
import PackageDescription

// Pure domain tests can run without an iOS simulator. UI remains in the Xcode app target.
let package = Package(
    name: "QuestifyCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "QuestifyCore", targets: ["QuestifyCore"])],
    targets: [
        .target(name: "QuestifyCore", path: "Core"),
        .testTarget(name: "QuestifyCoreTests", dependencies: ["QuestifyCore"], path: "Tests/CoreTests")
    ]
)
