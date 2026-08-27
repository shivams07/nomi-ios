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
    // Authorised by design §2.15, for one reason only: naming `ByteBuffer` at
    // the call site. `NIOIMAPCore.ResponseParser` is already reachable through
    // `import NIOIMAP` (NIOIMAP.swift is a single `@_exported import
    // NIOIMAPCore`), but `ByteBuffer` is not re-exported — ResponseParser.swift
    // says `import struct NIO.ByteBuffer`, plainly.
    //
    // `from: "2.64.0"` mirrors swift-nio-imap's own floor exactly, so this adds
    // no new constraint to the resolved graph. NIOCore, never the `NIO`
    // umbrella: the umbrella drags in NIOPosix — BSD sockets and event loops —
    // which is the thing we are avoiding on iOS.
    .package(url: "https://github.com/apple/swift-nio", from: "2.64.0"),
    .package(url: "https://github.com/CoreOffice/CoreXLSX.git", from: "0.14.2"),
    .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
  ],
  targets: [
    .target(
      name: "NomiIngest",
      dependencies: [
        "NomiCore",
        .product(name: "NIOIMAP", package: "swift-nio-imap"),
        // §2.15. NIOCore only — not NIOPosix, not the NIO umbrella.
        .product(name: "NIOCore", package: "swift-nio"),
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
