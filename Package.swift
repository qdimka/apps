// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "apps",
    platforms: [.macOS(.v14)],
    products: [.library(name: "AppsCore", targets: ["AppsCore"]), .executable(name: "apps", targets: ["Apps"])],
    targets: [
        .target(name: "AppsCore"),
        .executableTarget(name: "Apps", dependencies: ["AppsCore"]),
        .executableTarget(name: "AppsCoreChecks", dependencies: ["AppsCore"], path: "Tests/AppsCoreTests")
    ]
)
