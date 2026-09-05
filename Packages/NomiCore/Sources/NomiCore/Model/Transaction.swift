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

/// Why a row was flagged **at insert time**, and only at insert time.
///
/// It exists so that clearing the flag can be specific. Assigning an account to
/// a row flagged because Layer 2 guessed its *amount* must not mark that amount
/// reviewed; without a reason, "the user assigned an account" and "the row is
/// fine now" are the same event and the second one is a lie.
///
/// `nil` means the flag was set by the pipeline (a near merge, an account
/// conflict) rather than by the ingester, and nothing here may clear it.
public enum NeedsReviewReason: String, Codable, Sendable {
  /// A pack match whose account could not be identified (§1.2).
  case unidentifiedAccount
  /// Layer 2 read it - recall with a human gate.
  case heuristic
  /// A real candidate nobody could read; `amountMinor` is 0.
  case unparseable
  /// The `Date:` header was unreadable and the date is the epoch. Overrides
  /// the others: a 1970 row sorts to the bottom of the ledger and is never
  /// seen again, so that is the thing to say about it.
  case unreadableDate
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

  // C4. All three optional with a `nil` default and no schema version bump, so
  // CloudKit accepts them (R5) and every row already on a device reads `nil`.
  // None of them reaches `dedupeKey` - `DedupeKeyIndependenceTests` is the
  // guard on that.

  /// The sending bank's mail domain, lowercased. Mail rows only.
  public var senderDomain: String?

  /// The trailing four digits of the account or card the mail named. Mail rows
  /// only. Normalised to exactly four digits, or absent.
  public var cardFragment: String?

  /// `NeedsReviewReason`, insert-time only. See that type.
  public var needsReviewReasonRaw: String?

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
    updatedAt: Date = Date(),
    senderDomain: String? = nil,
    cardFragment: String? = nil,
    needsReviewReasonRaw: String? = nil
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
    self.senderDomain = senderDomain
    self.cardFragment = cardFragment
    self.needsReviewReasonRaw = needsReviewReasonRaw
  }

  public var needsReviewReason: NeedsReviewReason? {
    get { needsReviewReasonRaw.flatMap(NeedsReviewReason.init(rawValue:)) }
    set { needsReviewReasonRaw = newValue?.rawValue }
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
