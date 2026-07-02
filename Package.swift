// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KindleDashboard",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "KindleDashboard", targets: ["KindleDashboard"])
    ],
    targets: [
        .executableTarget(
            name: "KindleDashboard"
        )
    ]
)
