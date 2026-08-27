// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "NomiIngest",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [
    .library(name: "NomiIngest", targets: ["NomiIngest"])
  ],
  dependencies: [
    .package(path: "../NomiCore"),
    .package(url: "https://github.com/apple/swift-nio-imap.git", from: "0.4.0"),
    .package(url: "https://github.com/CoreOffice/CoreXLSX.git", from: "0.14.2"),
    .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
  ],
  targets: [
    .target(
      name: "NomiIngest",
      dependencies: [
        "NomiCore",
        .product(name: "NIOIMAP", package: "swift-nio-imap"),
        "CoreXLSX",
        "SwiftSoup",
      ],
      // senders.json is Layer 1's data and must ship in the bundle. Authorised
      // by design §2.10, which permits this declaration on this target and
      // NOTHING else in this file: no dependency added, removed or re-pinned,
      // no platforms change, no new target.
      resources: [.process("Resources")],
      swiftSettings: [.enableExperimentalFeature("StrictConcurrency=targeted")]
    ),
    .testTarget(
      name: "NomiIngestTests",
      dependencies: ["NomiIngest"]
    ),
  ]
)
