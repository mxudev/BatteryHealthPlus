// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BatteryHealthPlus",
    platforms: [.macOS(.v14)],
    products: [.library(name: "PowerCore", targets: ["PowerCore"]),
               .executable(name: "power-probe", targets: ["PowerProbe"])],
    targets: [
        .target(name: "PowerCore", linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "PowerProbe", dependencies: ["PowerCore"]),
        .testTarget(name: "PowerCoreTests", dependencies: ["PowerCore"])
    ]
)
