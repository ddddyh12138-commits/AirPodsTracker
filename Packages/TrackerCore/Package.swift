// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TrackerCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "TrackerCore", targets: ["TrackerCore"])],
    targets: [.target(name: "TrackerCore"), .testTarget(name: "TrackerCoreTests", dependencies: ["TrackerCore"])]
)
