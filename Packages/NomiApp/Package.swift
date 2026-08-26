// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "NomiApp",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [
    .library(name: "NomiApp", targets: ["NomiApp"])
  ],
  dependencies: [
    .package(path: "../NomiCore"),
    .package(path: "../NomiIngest"),
    .package(path: "../NomiUI"),
  ],
  targets: [
    .target(
      name: "NomiApp",
      dependencies: ["NomiCore", "NomiIngest", "NomiUI"],
      swiftSettings: [.enableExperimentalFeature("StrictConcurrency=targeted")]
    ),
    .testTarget(
      name: "NomiAppTests",
      dependencies: ["NomiApp"]
    ),
  ]
)
