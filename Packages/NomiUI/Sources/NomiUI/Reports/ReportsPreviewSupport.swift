import Foundation
import NomiCore
import NomiPreview

/// Preview-only fixtures for the Reports screen. `PreviewData.transactions`
/// is debit-only and spans a fixed 12 months, which can't demonstrate a
/// "Received" figure or a deliberately-short trend window — so, same
/// reasoning as `BudgetsPreviewSupport`, this builds a small fresh dataset
/// instead of depending on shared preview data. `Transaction`/`Category` are
/// `@Model` types; constructing them here is safe because this file is
/// consumed only by `#Preview` bodies, which `swift test` compiles but never
/// executes — the SwiftData bundle-name crash `InMemoryModelContainer.swift`
/// documents only fires when an `@Model` instance is actually constructed at
/// test *runtime*.
enum ReportsPreviewSupport {
  private static let categoryID = UUID(uuidString: "00000000-0000-0000-0000-000000000601")!
  private static let secondCategoryID = UUID(uuidString: "00000000-0000-0000-0000-000000000602")!

  private static let categories: [NomiCore.Category] = [
    NomiCore.Category(id: categoryID, name: "Food & Dining", symbolName: "fork.knife", paletteSlot: 0, isSystem: true, sortIndex: 0),
    NomiCore.Category(id: secondCategoryID, name: "Salary", symbolName: "banknote", paletteSlot: 4, isSystem: true, sortIndex: 1),
  ]

  /// `monthCount` months of data, ending at `anchor`'s month, one debit and
  /// one credit transaction per month. Deterministic transaction IDs (not
  /// `UUID()`) so two calls with the same `monthCount`/`anchor` build
  /// value-identical data — the calendar-month and financial-year previews
  /// below call this with the same arguments specifically so they render
  /// "the same underlying data" (the AC's own wording), not two independently
  /// randomised datasets that merely look similar.
  @MainActor
  static func makeInsightsStore(monthCount: Int, anchor: Date = Date(), calendar: Calendar = .current) -> FakeInsightsStore {
    var transactions: [Transaction] = []
    for offset in 0..<monthCount {
      guard let monthDate = calendar.date(byAdding: .month, value: -offset, to: anchor) else { continue }
      let debitDate = calendar.date(bySetting: .day, value: 5, of: monthDate) ?? monthDate
      let creditDate = calendar.date(bySetting: .day, value: 1, of: monthDate) ?? monthDate
      transactions.append(Transaction(
        id: transactionID(offset: offset, suffix: 0),
        date: debitDate,
        descriptionText: "SWIGGY/PAYMENT/REF\(offset)",
        merchantName: "SWIGGY",
        amountMinor: 4500,
        directionRaw: Direction.debit.rawValue,
        categoryID: categoryID
      ))
      transactions.append(Transaction(
        id: transactionID(offset: offset, suffix: 1),
        date: creditDate,
        descriptionText: "SALARY CREDIT",
        merchantName: "Employer",
        amountMinor: 90_000_00,
        directionRaw: Direction.credit.rawValue,
        categoryID: secondCategoryID
      ))
    }
    return FakeInsightsStore(transactions: transactions, categories: categories, accounts: [], budgets: [])
  }

  private static func transactionID(offset: Int, suffix: Int) -> UUID {
    UUID(uuidString: "00000000-0000-0000-0000-" + String(format: "%012d", offset * 10 + suffix))!
  }
}
