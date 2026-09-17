import AppIntents

/// Makes this package's intents visible to the app that links it (U23).
///
/// Intents declared inside a SwiftPM module are not discovered on their own.
/// The module vends an `AppIntentsPackage`, and the app target names it in its
/// own — `App/NomiIntentsPackage.swift`. Without both halves the build still
/// succeeds and Shortcuts simply shows nothing, which is the failure mode this
/// pair exists to avoid.
public struct NomiAppIntentsPackage: AppIntentsPackage {}

/// The shortcuts offered without the user assembling them themselves.
///
/// Two, and the second one revises a decision. This used to say only "Add
/// Transaction" belonged here, because "a query intent nobody asked for is
/// clutter" — a provider's shortcuts are surfaced unprompted in Spotlight and
/// the Shortcuts app, so each one spends attention the app has not been given.
/// That reasoning holds for a query nobody asked for. "How much have I spent"
/// is the question the app exists to answer and is W2-7's whole point, so it
/// earns its place; the bar it had to clear is stated here rather than quietly
/// dropped.
///
/// Still two, and not one per period. `SpendingSummaryIntent.period` has a
/// default, so one phrase covers the common case and Siri asks when it does
/// not.
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

    AppShortcut(
      intent: SpendingSummaryIntent(),
      phrases: [
        "How much have I spent in \(.applicationName)",
        "Check my spending in \(.applicationName)",
      ],
      shortTitle: "Spending Summary",
      systemImageName: "chart.pie")
  }
}
