import AppIntents
import NomiApp

/// The app half of the pair described in `NomiShortcuts.swift` (U23).
///
/// `AddTransactionIntent` lives in the NomiApp package, not in this target, so
/// the intents metadata processor only finds it if the app declares the
/// package as included. This file is the entire reason the Shortcuts app has
/// anything to show.
///
/// Its presence is also what makes `appintentsmetadataprocessor` run during
/// `xcodebuild` — that step is skipped outright when no `AppIntentsPackage` is
/// found, so its line in the build log is the proof this wiring took.
struct NomiIntentsPackage: AppIntentsPackage {
  static var includedPackages: [any AppIntentsPackage.Type] {
    [NomiAppIntentsPackage.self]
  }
}
