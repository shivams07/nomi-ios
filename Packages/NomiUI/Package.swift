// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "NomiUI",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [
    .library(name: "NomiUI", targets: ["NomiUI"])
  ],
  dependencies: [
    .package(path: "../NomiCore"),
    .package(path: "../NomiPreview"),
  ],
  targets: [
    .target(
      name: "NomiUI",
      dependencies: ["NomiCore", "NomiPreview"],
      swiftSettings: [.enableExperimentalFeature("StrictConcurrency=targeted")]
    ),
    .testTarget(
      name: "NomiUITests",
      dependencies: ["NomiUI"]
    ),
  ]
)
