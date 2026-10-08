// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "ToolboxApp",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ToolboxApp", targets: ["ToolboxApp"])],
    targets: [
        .executableTarget(
            name: "ToolboxApp",
            resources: [.process("Resources")]
        )
    ]
)
