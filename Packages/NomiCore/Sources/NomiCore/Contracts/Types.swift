import Foundation

public struct TransactionFilter: Sendable, Equatable {
  public var categoryIDs: Set<UUID> = []
  public var accountIDs: Set<UUID> = []
  public var dateRange: ClosedRange<Date>?
  public var uncategorizedOnly: Bool = false
  public var searchText: String = ""

  public init(
    categoryIDs: Set<UUID> = [],
    accountIDs: Set<UUID> = [],
    dateRange: ClosedRange<Date>? = nil,
    uncategorizedOnly: Bool = false,
    searchText: String = ""
  ) {
    self.categoryIDs = categoryIDs
    self.accountIDs = accountIDs
    self.dateRange = dateRange
    self.uncategorizedOnly = uncategorizedOnly
    self.searchText = searchText
  }
}

public struct ManualTransactionDraft: Sendable {
  public var date: Date
  public var amountMinor: Int
  public var descriptionText: String
  public var direction: Direction
  public var categoryID: UUID?
  public var accountID: UUID?

  public init(
    date: Date = Date(),
    amountMinor: Int,
    descriptionText: String,
    direction: Direction = .debit,
    categoryID: UUID? = nil,
    accountID: UUID? = nil
  ) {
    self.date = date
    self.amountMinor = amountMinor
    self.descriptionText = descriptionText
    self.direction = direction
    self.categoryID = categoryID
    self.accountID = accountID
  }
}

public struct RuleApplyResult: Sendable {
  public let matched: Int
  public let recategorized: Int

  public init(matched: Int, recategorized: Int) {
    self.matched = matched
    self.recategorized = recategorized
  }
}

public enum InsightPeriod: Sendable, Equatable, Hashable {
  case month(year: Int, month: Int)
  case financialYear(startingYear: Int)
  case trailingMonths(Int)
  case allTime
}

public enum PeriodBasis: String, Sendable, Codable, CaseIterable {
  case calendarMonth, financialYear
}

public struct CategorySlice: Sendable, Identifiable {
  public let id: UUID
  public let name: String
  public let paletteSlot: Int
  public let totalMinor: Int
  public let share: Double

  public init(id: UUID, name: String, paletteSlot: Int, totalMinor: Int, share: Double) {
    self.id = id
    self.name = name
    self.paletteSlot = paletteSlot
    self.totalMinor = totalMinor
    self.share = share
  }
}

public struct DayBucket: Sendable, Identifiable {
  public let id: Date
  public let debitMinor: Int

  public init(id: Date, debitMinor: Int) {
    self.id = id
    self.debitMinor = debitMinor
  }
}

public struct MonthBucket: Sendable, Identifiable {
  public let id: Date
  public let debitMinor: Int
  public let creditMinor: Int

  public init(id: Date, debitMinor: Int, creditMinor: Int) {
    self.id = id
    self.debitMinor = debitMinor
    self.creditMinor = creditMinor
  }
}

public struct MerchantTotal: Sendable, Identifiable {
  public let id: String
  public let label: String
  public let totalMinor: Int

  public init(id: String, label: String, totalMinor: Int) {
    self.id = id
    self.label = label
    self.totalMinor = totalMinor
  }
}

public struct PeriodInsights: Sendable {
  public let period: InsightPeriod
  public let debitMinor: Int
  public let creditMinor: Int
  public let netMinor: Int
  public let priorDebitMinor: Int?
  public let priorCreditMinor: Int?
  public let transactionCount: Int
  public let byDay: [DayBucket]
  public let byCategory: [CategorySlice]
  public let topMerchants: [MerchantTotal]
  public let needsReviewCount: Int
  public let uncategorizedCount: Int

  public init(
    period: InsightPeriod,
    debitMinor: Int,
    creditMinor: Int,
    netMinor: Int,
    priorDebitMinor: Int?,
    priorCreditMinor: Int?,
    transactionCount: Int,
    byDay: [DayBucket],
    byCategory: [CategorySlice],
    topMerchants: [MerchantTotal],
    needsReviewCount: Int,
    uncategorizedCount: Int
  ) {
    self.period = period
    self.debitMinor = debitMinor
    self.creditMinor = creditMinor
    self.netMinor = netMinor
    self.priorDebitMinor = priorDebitMinor
    self.priorCreditMinor = priorCreditMinor
    self.transactionCount = transactionCount
    self.byDay = byDay
    self.byCategory = byCategory
    self.topMerchants = topMerchants
    self.needsReviewCount = needsReviewCount
    self.uncategorizedCount = uncategorizedCount
  }
}

public struct AccountSummary: Sendable, Identifiable {
  public let id: UUID
  public let displayName: String
  public let institution: String
  public let lastFour: String
  public let kindRaw: String
  public let trackedBalanceMinor: Int
  public let transactionCount: Int
  public let trackingSince: Date?
  public let isArchived: Bool

  public init(
    id: UUID,
    displayName: String,
    institution: String,
    lastFour: String,
    kindRaw: String,
    trackedBalanceMinor: Int,
    transactionCount: Int,
    trackingSince: Date?,
    isArchived: Bool
  ) {
    self.id = id
    self.displayName = displayName
    self.institution = institution
    self.lastFour = lastFour
    self.kindRaw = kindRaw
    self.trackedBalanceMinor = trackedBalanceMinor
    self.transactionCount = transactionCount
    self.trackingSince = trackingSince
    self.isArchived = isArchived
  }
}

public struct BudgetProgress: Sendable, Identifiable {
  public let id: UUID
  public let categoryName: String
  public let paletteSlot: Int
  public let budgetMinor: Int
  public let spentMinor: Int
  public let fraction: Double
  public let periodKey: String

  public init(
    id: UUID,
    categoryName: String,
    paletteSlot: Int,
    budgetMinor: Int,
    spentMinor: Int,
    fraction: Double,
    periodKey: String
  ) {
    self.id = id
    self.categoryName = categoryName
    self.paletteSlot = paletteSlot
    self.budgetMinor = budgetMinor
    self.spentMinor = spentMinor
    self.fraction = fraction
    self.periodKey = periodKey
  }
}

public struct NotificationSettings: Sendable, Codable, Equatable {
  public var budgetAlertsEnabled: Bool = false
  public var thresholdFraction: Double = 0.9

  public init(budgetAlertsEnabled: Bool = false, thresholdFraction: Double = 0.9) {
    self.budgetAlertsEnabled = budgetAlertsEnabled
    self.thresholdFraction = thresholdFraction
  }
}

public enum MailError: Error, Sendable, Equatable {
  case authenticationFailed
  case connectionFailed
  case unknown(String)
}

public enum MailConnectionState: Sendable, Equatable {
  case disconnected
  case connecting
  case connected(address: String, lastSync: Date?)
  case failed(MailError)
}

public struct BackfillProgress: Sendable {
  public let scanned: Int
  public let total: Int
  public let created: Int

  public init(scanned: Int, total: Int, created: Int) {
    self.scanned = scanned
    self.total = total
    self.created = created
  }
}

public struct UnmatchedSender: Sendable, Hashable {
  public let domain: String
  public let count: Int

  public init(domain: String, count: Int) {
    self.domain = domain
    self.count = count
  }
}

public struct SyncSummary: Sendable {
  public let scanned: Int
  public let created: Int
  public let merged: Int
  public let flagged: Int
  public let packMatched: Int
  public let heuristicMatched: Int
  public let unmatchedSenders: [UnmatchedSender]

  public init(
    scanned: Int,
    created: Int,
    merged: Int,
    flagged: Int,
    packMatched: Int,
    heuristicMatched: Int,
    unmatchedSenders: [UnmatchedSender]
  ) {
    self.scanned = scanned
    self.created = created
    self.merged = merged
    self.flagged = flagged
    self.packMatched = packMatched
    self.heuristicMatched = heuristicMatched
    self.unmatchedSenders = unmatchedSenders
  }
}

public struct IMAPCredentials: Sendable {
  public let host: String
  public let port: Int
  public let address: String
  public let password: String

  public init(host: String, port: Int, address: String, password: String) {
    self.host = host
    self.port = port
    self.address = address
    self.password = password
  }
}

public struct ImportPreview: Sendable {
  public let formatSignature: String
  public let detectedBankLabel: String?
  public let suggestedMapping: ColumnMapping?
  public let headers: [String]
  public let sampleRows: [[String]]
  public let parseableRowCount: Int

  public init(
    formatSignature: String,
    detectedBankLabel: String?,
    suggestedMapping: ColumnMapping?,
    headers: [String],
    sampleRows: [[String]],
    parseableRowCount: Int
  ) {
    self.formatSignature = formatSignature
    self.detectedBankLabel = detectedBankLabel
    self.suggestedMapping = suggestedMapping
    self.headers = headers
    self.sampleRows = sampleRows
    self.parseableRowCount = parseableRowCount
  }
}

public enum DirectionStrategy: Codable, Sendable, Equatable {
  case signedAmount
  case separateColumns(debit: Int, credit: Int)
  case flagColumn(index: Int, debitValues: [String])
}

public struct ColumnMapping: Codable, Sendable, Equatable {
  public var dateColumn: Int
  public var descriptionColumn: Int
  public var amountColumn: Int
  public var referenceColumn: Int?
  public var directionStrategy: DirectionStrategy
  public var dateFormat: String

  public init(
    dateColumn: Int,
    descriptionColumn: Int,
    amountColumn: Int,
    referenceColumn: Int? = nil,
    directionStrategy: DirectionStrategy,
    dateFormat: String
  ) {
    self.dateColumn = dateColumn
    self.descriptionColumn = descriptionColumn
    self.amountColumn = amountColumn
    self.referenceColumn = referenceColumn
    self.directionStrategy = directionStrategy
    self.dateFormat = dateFormat
  }
}

public struct ImportSummary: Sendable {
  public let created: Int
  public let merged: Int
  public let skipped: Int

  public init(created: Int, merged: Int, skipped: Int) {
    self.created = created
    self.merged = merged
    self.skipped = skipped
  }
}

public enum ImportError: Error, Sendable {
  case unreadableEncoding
  case unsupportedLegacyXLS
  case malformedStructure(reason: String)
  case noParseableRows
}
