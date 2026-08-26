// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "NomiPreview",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [
    .library(name: "NomiPreview", targets: ["NomiPreview"])
  ],
  dependencies: [
    .package(path: "../NomiCore")
  ],
  targets: [
    .target(
      name: "NomiPreview",
      dependencies: ["NomiCore"],
      swiftSettings: [.enableExperimentalFeature("StrictConcurrency=targeted")]
    ),
    .testTarget(
      name: "NomiPreviewTests",
      dependencies: ["NomiPreview"]
    ),
  ]
)
