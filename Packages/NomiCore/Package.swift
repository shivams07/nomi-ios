// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "NomiCore",
  platforms: [.iOS(.v17)],
  products: [
    .library(name: "NomiCore", targets: ["NomiCore"])
  ],
  targets: [
    .target(
      name: "NomiCore",
      swiftSettings: [.enableExperimentalFeature("StrictConcurrency=targeted")]
    ),
    .testTarget(
      name: "NomiCoreTests",
      dependencies: ["NomiCore"]
    ),
  ]
)
