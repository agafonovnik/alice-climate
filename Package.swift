// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "AliceClimate",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "AliceClimate", targets: ["AliceClimate"])],
    targets: [
        .target(name: "ClimateCore"),
        .executableTarget(name: "AliceClimate", dependencies: ["ClimateCore"]),
        .executableTarget(name: "ClimateCoreTests", dependencies: ["ClimateCore"], path: "Tests/ClimateCoreTests")
    ]
)
