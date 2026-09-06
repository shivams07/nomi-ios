import AppIntents

/// Makes this package's intents visible to the app that links it (U23).
///
/// Intents declared inside a SwiftPM module are not discovered on their own.
/// The module vends an `AppIntentsPackage`, and the app target names it in its
/// own — `App/NomiIntentsPackage.swift`. Without both halves the build still
/// succeeds and Shortcuts simply shows nothing, which is the failure mode this
/// pair exists to avoid.
public struct NomiAppIntentsPackage: AppIntentsPackage {}

/// The one shortcut offered without the user assembling it themselves.
///
/// Only "Add Transaction". A provider's shortcuts are surfaced unprompted in
/// Spotlight and the Shortcuts app, so each one spends attention the app has
/// not been given; a query intent nobody asked for is clutter. Reading the
/// ledger back is deliberately not here.
public struct NomiShortcuts: AppShortcutsProvider {
  public static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: AddTransactionIntent(),
      phrases: [
        "Add a transaction to \(.applicationName)",
        "Record an expense in \(.applicationName)",
        "Add an expense to \(.applicationName)",
      ],
      shortTitle: "Add Transaction",
      systemImageName: "indianrupeesign.circle")
  }
}
