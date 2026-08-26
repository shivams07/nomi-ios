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
      resources: [
        .copy("Resources/Fonts/Montserrat-Medium.otf"),
        .copy("Resources/Fonts/Montserrat-SemiBold.otf"),
        .copy("Resources/Fonts/Montserrat-Bold.otf"),
        .copy("Resources/Fonts/Inter-Regular.otf"),
      ],
      swiftSettings: [.enableExperimentalFeature("StrictConcurrency=targeted")]
    ),
    .testTarget(
      name: "NomiUITests",
      dependencies: ["NomiUI"]
    ),
  ]
)
