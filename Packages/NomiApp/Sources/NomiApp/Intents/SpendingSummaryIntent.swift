import AppIntents
import Foundation
import NomiCore

/// "How much have I spent?" from Siri, the Shortcuts app, or a Home Screen
/// shortcut (W2-7).
///
/// `openAppWhenRun = false`, for the reason `AddTransactionIntent` has it: the
/// point of asking Siri is not having to open the app.
///
/// **Read-only.** It goes through `AppServices.shared.insightsStore`, the same
/// `insights(for:)` the dashboard reads, so the number Siri says and the number
/// on the Dashboard are the same number computed once — not a second sum with
/// its own opinion about foreign currency, archived accounts or what counts as
/// spend.
///
/// No widget and no app group. A widget needs the SwiftData store relocated
/// into a shared container, which is a migration on live data; it is a wave-3
/// spec, not something to smuggle in behind an intent.
struct SpendingSummaryIntent: AppIntent {
  static let title: LocalizedStringResource = "Spending Summary"
  static let description = IntentDescription(
    "Ask Nomi how much you have spent, for a period or a category.")
  static let openAppWhenRun = false

  @Parameter(title: "Period", default: .thisMonth)
  var period: SpendingSummaryPeriod

  /// Optional: no category means everything. Reuses `CategoryEntity` from
  /// `AddTransactionIntent` — the same query, so Siri resolves a spoken
  /// category name the same way in both intents rather than having two
  /// vocabularies for one set of names.
  @Parameter(title: "Category")
  var category: CategoryEntity?

  static var parameterSummary: some ParameterSummary {
    Summary("How much did I spend in \(\.$period)") {
      \.$category
    }
  }

  /// `@MainActor` because `InsightsStore` is: it reads through the container's
  /// `mainContext`.
  ///
  /// The category total comes from `byCategory` rather than a second query.
  /// That slice is the dashboard's own per-category spend, so a category the
  /// user asks about is answered with the figure the ring on the dashboard
  /// draws. A category with no spend has no slice, which is zero — and zero has
  /// its own sentence.
  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let calendar = Calendar.current
    let insightPeriod = IntentSummaryFormatting.insightPeriod(
      for: period.window, now: Date(), calendar: calendar)

    let insights = try AppServices.shared.insightsStore.insights(for: insightPeriod)

    let spentMinor: Int
    if let category {
      spentMinor = insights.byCategory.first { $0.id == category.id }?.totalMinor ?? 0
    } else {
      spentMinor = insights.debitMinor
    }

    let dialog = IntentSummaryFormatting.dialog(
      spentMinor: spentMinor,
      period: insightPeriod,
      categoryName: category?.name
    )
    return .result(dialog: IntentDialog(stringLiteral: dialog))
  }
}

/// The period Siri asks for.
///
/// A `String`-backed `AppEnum` so the stored raw values survive a reordering of
/// the cases — a shortcut the user built keeps meaning what they built it to
/// mean.
///
/// `window` is the only mapping onto `IntentSummaryFormatting.Window`, which is
/// what keeps `AppIntents` out of the file every decision is tested in.
enum SpendingSummaryPeriod: String, AppEnum {
  case thisMonth, lastMonth, thisFinancialYear

  static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Period")

  static let caseDisplayRepresentations: [SpendingSummaryPeriod: DisplayRepresentation] = [
    .thisMonth: "this month",
    .lastMonth: "last month",
    .thisFinancialYear: "this financial year",
  ]

  var window: IntentSummaryFormatting.Window {
    switch self {
    case .thisMonth: return .thisMonth
    case .lastMonth: return .lastMonth
    case .thisFinancialYear: return .thisFinancialYear
    }
  }
}
