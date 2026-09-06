import AppIntents
import Foundation
import NomiCore
import SwiftData

/// "Add Transaction" from Siri, the Shortcuts app, or a Home Screen shortcut.
///
/// `openAppWhenRun = false`: the point of a quick-add is that it is quicker
/// than opening the app. It writes through `AppServices.shared.transactionStore`
/// — the same `add` the entry sheet calls, so the row gets the same rule pass,
/// the same dedupe key and the same cache invalidation. There is no second
/// write path here and there must not be.
///
/// No widget and no app group. A widget needs the store relocated to a shared
/// container, which is a migration and a schema decision, and it is called out
/// in the design's Risks rather than smuggled in behind an intent.
struct AddTransactionIntent: AppIntent {
  static let title: LocalizedStringResource = "Add Transaction"
  static let description = IntentDescription(
    "Record a transaction in Nomi without opening the app.")
  static let openAppWhenRun = false

  /// Text, not a number. `@Parameter` requires `_IntentValue` and `Decimal`
  /// does not conform; `Double` cannot represent 12.99 exactly, which is the
  /// one thing `IntentDraftMapping` exists to guarantee. Parsed and validated
  /// there, and declined out loud if it is not a number.
  @Parameter(title: "Amount", description: "In rupees, e.g. 249.50")
  var amount: String

  @Parameter(title: "Description", description: "What it was for")
  var note: String?

  @Parameter(title: "Category")
  var category: CategoryEntity?

  @Parameter(title: "Income", default: false)
  var isIncome: Bool

  static var parameterSummary: some ParameterSummary {
    Summary("Add \(\.$amount) for \(\.$note)") {
      \.$category
      \.$isIncome
    }
  }

  /// `@MainActor` because `TransactionStore` is: it writes through the
  /// container's `mainContext`, the same one every `@Query` in the app reads.
  ///
  /// Errors are thrown as `AppIntentError`s with copy the user hears, rather
  /// than swallowed — a quick-add that silently does nothing is worse than one
  /// that says why it declined.
  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let draft: ManualTransactionDraft
    switch IntentDraftMapping.draft(
      amountText: amount, note: note, categoryID: category?.id, isIncome: isIncome)
    {
    case .success(let made):
      draft = made
    case .failure(let failure):
      throw AddTransactionError(failure)
    }

    _ = try AppServices.shared.transactionStore.add(draft)
    return .result(dialog: IntentDialog(stringLiteral: IntentDraftMapping.confirmation(for: draft)))
  }
}

/// What the user hears when the intent declines.
///
/// `CustomLocalizedStringResourceConvertible` is what makes AppIntents read the
/// message out instead of saying "the app encountered an error", which is the
/// difference between a user fixing their input and a user giving up on the
/// shortcut.
enum AddTransactionError: Error, CustomLocalizedStringResourceConvertible {
  case tooPrecise
  case outOfRange
  case blankDescription
  case notANumber

  init(_ failure: IntentDraftMapping.Failure) {
    switch failure {
    case .tooPrecise: self = .tooPrecise
    case .outOfRange: self = .outOfRange
    case .blankDescription: self = .blankDescription
    case .notANumber: self = .notANumber
    }
  }

  var localizedStringResource: LocalizedStringResource {
    switch self {
    case .tooPrecise:
      return "Amounts can have at most two decimal places."
    case .outOfRange:
      return "That is not an amount Nomi can record."
    case .blankDescription:
      return "Say what the transaction was for."
    case .notANumber:
      return "That amount is not a number Nomi can read."
    }
  }
}

/// The categories Siri can offer, and resolve a spoken name against.
///
/// Queries the container directly rather than going through `InsightsStore`:
/// there is no aggregate here, only names, and the intent runs in a process
/// where no screen has warmed a cache.
struct CategoryEntity: AppEntity, Identifiable {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Category")
  static let defaultQuery = CategoryEntityQuery()

  let id: UUID
  let name: String

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(name)")
  }
}

struct CategoryEntityQuery: EntityQuery {
  @MainActor
  func entities(for identifiers: [UUID]) async throws -> [CategoryEntity] {
    try all().filter { identifiers.contains($0.id) }
  }

  @MainActor
  func suggestedEntities() async throws -> [CategoryEntity] {
    try all()
  }

  @MainActor
  private func all() throws -> [CategoryEntity] {
    let context = AppServices.shared.container.mainContext
    let categories = try context.fetch(
      FetchDescriptor<NomiCore.Category>(sortBy: [SortDescriptor(\.name)]))
    return categories.map { CategoryEntity(id: $0.id, name: $0.name) }
  }
}
