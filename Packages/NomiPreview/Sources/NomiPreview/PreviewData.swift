import Foundation
import NomiCore

/// Seed data shared by every fake store. Realistic enough that Morgan's SwiftUI
/// previews and UI tests have something to render: 4 categories, 4 accounts (one
/// archived), 2 rules, 2 budgets (one over 90%, one under), >=12 months of dated
/// transactions, at least one merged row and one needsReview row.
enum PreviewData {
  static let categories: [Category] = {
    let names: [(String, String, Int)] = [
      ("Food & Dining", "fork.knife", 0),
      ("Shopping", "bag", 1),
      ("Transport", "car", 2),
      ("Bills & Utilities", "bolt", 3),
    ]
    return names.enumerated().map { index, entry in
      Category(
        id: UUID(uuidString: String(format: "00000000-0000-0000-0000-0000000001%02d", index))!,
        name: entry.0,
        symbolName: entry.1,
        paletteSlot: entry.2,
        isSystem: true,
        sortIndex: index
      )
    }
  }()

  static let accounts: [Account] = [
    Account(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
      displayName: "HDFC •• 4471",
      institution: "HDFC Bank",
      lastFour: "4471",
      kindRaw: "bank",
      isArchived: false,
      createdAt: Date(timeIntervalSinceNow: -400 * 86400)
    ),
    Account(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000202")!,
      displayName: "ICICI •• 8890",
      institution: "ICICI Bank",
      lastFour: "8890",
      kindRaw: "bank",
      isArchived: false,
      createdAt: Date(timeIntervalSinceNow: -380 * 86400)
    ),
    Account(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000203")!,
      displayName: "HDFC Card •• 1123",
      institution: "HDFC Bank",
      lastFour: "1123",
      kindRaw: "card",
      isArchived: false,
      createdAt: Date(timeIntervalSinceNow: -300 * 86400)
    ),
    Account(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000204")!,
      displayName: "Old Wallet",
      institution: "Paytm",
      lastFour: "0000",
      kindRaw: "wallet",
      isArchived: true,
      createdAt: Date(timeIntervalSinceNow: -500 * 86400)
    ),
  ]

  static let rules: [Rule] = [
    Rule(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!,
      pattern: "*SWIGGY*",
      categoryID: categories[0].id,
      priority: 0,
      isEnabled: true,
      createdAt: Date(timeIntervalSinceNow: -200 * 86400)
    ),
    Rule(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000302")!,
      pattern: "*AMAZON*",
      categoryID: categories[1].id,
      priority: 1,
      isEnabled: true,
      createdAt: Date(timeIntervalSinceNow: -190 * 86400)
    ),
  ]

  static let transactions: [Transaction] = makeTransactions()

  /// One budget over 90% of current-month spend, one comfortably under —
  /// derived from the actual seeded transactions so the property holds
  /// regardless of how the merchant rotation lands.
  static let budgets: [Budget] = {
    let calendar = Calendar.current
    let now = Date()
    let monthRange = dateRange(for: .month(year: calendar.component(.year, from: now), month: calendar.component(.month, from: now)), calendar: calendar)

    func currentMonthSpend(categoryID: UUID) -> Int {
      transactions
        .filter { monthRange.contains($0.date) && $0.categoryID == categoryID && $0.directionRaw == Direction.debit.rawValue }
        .reduce(0) { $0 + $1.amountMinor }
    }

    let overSpend = max(currentMonthSpend(categoryID: categories[0].id), 45_00)
    let underSpend = max(currentMonthSpend(categoryID: categories[1].id), 89_00)

    return [
      Budget(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000401")!,
        categoryID: categories[0].id,
        amountMinor: Int(Double(overSpend) / 0.95),
        isEnabled: true,
        createdAt: Date(timeIntervalSinceNow: -100 * 86400)
      ),
      Budget(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000402")!,
        categoryID: categories[1].id,
        amountMinor: underSpend * 4,
        isEnabled: true,
        createdAt: Date(timeIntervalSinceNow: -100 * 86400)
      ),
    ]
  }()

  private static func makeTransactions() -> [Transaction] {
    var result: [Transaction] = []
    let calendar = Calendar.current
    let now = Date()
    let merchants: [(String, UUID, Int)] = [
      ("SWIGGY", categories[0].id, 45_00),
      ("ZOMATO", categories[0].id, 32_00),
      ("AMAZON", categories[1].id, 120_00),
      ("FLIPKART", categories[1].id, 89_00),
      ("UBER", categories[2].id, 21_00),
      ("OLA", categories[2].id, 18_00),
      ("ELECTRICITY BOARD", categories[3].id, 210_00),
      ("BROADBAND ISP", categories[3].id, 60_00),
    ]

    var index = 0
    for monthOffset in 0..<12 {
      guard let monthDate = calendar.date(byAdding: .month, value: -monthOffset, to: now) else { continue }
      for day in stride(from: 2, through: 26, by: 5) {
        guard let date = calendar.date(bySetting: .day, value: day, of: monthDate) else { continue }
        let merchant = merchants[index % merchants.count]
        let account = accounts[index % 3]
        let description = "\(merchant.0)/PAYMENT/REF\(index)"
        let normalized = normalizeDescription(description)
        let key = makeDedupeKey(
          date: date,
          amountMinor: merchant.2,
          directionRaw: Direction.debit.rawValue,
          normalizedDescription: normalized
        )
        let transaction = Transaction(
          id: UUID(),
          date: date,
          descriptionText: description,
          merchantName: merchant.0,
          upiKindRaw: "p2m",
          counterpartyVPA: "\(merchant.0.lowercased())@okhdfcbank",
          normalizedDescription: normalized,
          amountMinor: merchant.2,
          currencyCode: "INR",
          directionRaw: Direction.debit.rawValue,
          categoryID: merchant.1,
          categorySourceRaw: CategorySource.rule.rawValue,
          appliedRuleID: nil,
          accountID: account.id,
          sourceRaw: IngestSource.email.rawValue,
          sourceRefs: [SourceRef(source: .email, externalID: "uid-\(index)", capturedAt: date)],
          mergedCount: 1,
          needsReview: false,
          dedupeKey: key,
          createdAt: date,
          updatedAt: date
        )
        result.append(transaction)
        index += 1
      }
    }

    // One merged row.
    if let sample = result.first {
      let merged = Transaction(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000501")!,
        date: sample.date,
        descriptionText: sample.descriptionText,
        merchantName: sample.merchantName,
        normalizedDescription: sample.normalizedDescription,
        amountMinor: sample.amountMinor,
        directionRaw: sample.directionRaw,
        categoryID: sample.categoryID,
        categorySourceRaw: sample.categorySourceRaw,
        accountID: sample.accountID,
        sourceRaw: IngestSource.file.rawValue,
        sourceRefs: [
          SourceRef(source: .email, externalID: "uid-merged-1", capturedAt: sample.date),
          SourceRef(source: .file, externalID: "csv-merged-1", capturedAt: sample.date),
        ],
        mergedCount: 2,
        needsReview: false,
        dedupeKey: sample.dedupeKey,
        createdAt: sample.date,
        updatedAt: sample.date
      )
      result.append(merged)
    }

    // One needsReview row (unidentified account).
    let reviewRow = Transaction(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000502")!,
      date: now,
      descriptionText: "UNKNOWN MERCHANT PAYMENT",
      normalizedDescription: normalizeDescription("UNKNOWN MERCHANT PAYMENT"),
      amountMinor: 99_00,
      directionRaw: Direction.debit.rawValue,
      categoryID: nil,
      categorySourceRaw: CategorySource.none.rawValue,
      accountID: nil,
      sourceRaw: IngestSource.email.rawValue,
      sourceRefs: [SourceRef(source: .email, externalID: "uid-review-1", capturedAt: now)],
      mergedCount: 1,
      needsReview: true,
      dedupeKey: makeDedupeKey(
        date: now,
        amountMinor: 99_00,
        directionRaw: Direction.debit.rawValue,
        normalizedDescription: normalizeDescription("UNKNOWN MERCHANT PAYMENT")
      ),
      createdAt: now,
      updatedAt: now
    )
    result.append(reviewRow)

    return result
  }
}
