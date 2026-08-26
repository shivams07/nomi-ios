// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "NomiIngest",
  platforms: [.iOS(.v17)],
  products: [
    .library(name: "NomiIngest", targets: ["NomiIngest"])
  ],
  dependencies: [
    .package(path: "../NomiCore"),
    .package(url: "https://github.com/apple/swift-nio-imap.git", from: "0.4.0"),
    .package(url: "https://github.com/CoreOffice/CoreXLSX.git", from: "0.9.1"),
    .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
  ],
  targets: [
    .target(
      name: "NomiIngest",
      dependencies: [
        "NomiCore",
        .product(name: "NIOIMAPCore", package: "swift-nio-imap"),
        "CoreXLSX",
        "SwiftSoup",
      ],
      swiftSettings: [.enableExperimentalFeature("StrictConcurrency=targeted")]
    ),
    .testTarget(
      name: "NomiIngestTests",
      dependencies: ["NomiIngest"]
    ),
  ]
)
