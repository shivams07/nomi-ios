import Foundation
import SwiftData

public enum Direction: String, Codable, CaseIterable, Sendable {
  case debit, credit
}

public enum IngestSource: String, Codable, Sendable {
  case email, file, manual
}

public enum CategorySource: String, Codable, Sendable {
  case none, rule, manual
}

public struct SourceRef: Codable, Hashable, Sendable {
  public let source: IngestSource
  public let externalID: String
  public let capturedAt: Date

  public init(source: IngestSource, externalID: String, capturedAt: Date) {
    self.source = source
    self.externalID = externalID
    self.capturedAt = capturedAt
  }
}

@Model
public final class Transaction {
  public var id: UUID = UUID()
  public var date: Date = Date()
  public var descriptionText: String = ""
  public var merchantName: String?
  public var upiKindRaw: String?
  public var counterpartyVPA: String?
  public var normalizedDescription: String = ""
  public var amountMinor: Int = 0
  public var currencyCode: String = "INR"
  public var directionRaw: String = Direction.debit.rawValue
  public var categoryID: UUID?
  public var categorySourceRaw: String = CategorySource.none.rawValue
  public var appliedRuleID: UUID?
  public var accountID: UUID?
  public var sourceRaw: String = IngestSource.manual.rawValue
  public var sourceRefs: [SourceRef] = []
  public var mergedCount: Int = 1
  public var needsReview: Bool = false
  public var dedupeKey: String = ""
  public var createdAt: Date = Date()
  public var updatedAt: Date = Date()

  public init(
    id: UUID = UUID(),
    date: Date = Date(),
    descriptionText: String = "",
    merchantName: String? = nil,
    upiKindRaw: String? = nil,
    counterpartyVPA: String? = nil,
    normalizedDescription: String = "",
    amountMinor: Int = 0,
    currencyCode: String = "INR",
    directionRaw: String = Direction.debit.rawValue,
    categoryID: UUID? = nil,
    categorySourceRaw: String = CategorySource.none.rawValue,
    appliedRuleID: UUID? = nil,
    accountID: UUID? = nil,
    sourceRaw: String = IngestSource.manual.rawValue,
    sourceRefs: [SourceRef] = [],
    mergedCount: Int = 1,
    needsReview: Bool = false,
    dedupeKey: String = "",
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.date = date
    self.descriptionText = descriptionText
    self.merchantName = merchantName
    self.upiKindRaw = upiKindRaw
    self.counterpartyVPA = counterpartyVPA
    self.normalizedDescription = normalizedDescription
    self.amountMinor = amountMinor
    self.currencyCode = currencyCode
    self.directionRaw = directionRaw
    self.categoryID = categoryID
    self.categorySourceRaw = categorySourceRaw
    self.appliedRuleID = appliedRuleID
    self.accountID = accountID
    self.sourceRaw = sourceRaw
    self.sourceRefs = sourceRefs
    self.mergedCount = mergedCount
    self.needsReview = needsReview
    self.dedupeKey = dedupeKey
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  public var direction: Direction {
    get { Direction(rawValue: directionRaw) ?? .debit }
    set { directionRaw = newValue.rawValue }
  }

  public var categorySource: CategorySource {
    get { CategorySource(rawValue: categorySourceRaw) ?? .none }
    set { categorySourceRaw = newValue.rawValue }
  }

  public var source: IngestSource {
    get { IngestSource(rawValue: sourceRaw) ?? .manual }
    set { sourceRaw = newValue.rawValue }
  }
}
