import Foundation
import NomiCore

/// A value-typed view of a `Rule`.
///
/// The pipeline's decision logic is written entirely against snapshots rather
/// than `@Model` types. That is not gold-plating: `swift test` cannot construct
/// a SwiftData `@Model` in this CI at all (see
/// `NomiCore/Support/InMemoryModelContainer.swift`), so logic that touches the
/// model types directly is logic no test on this project can execute.
public struct RuleSnapshot: Sendable, Equatable, Identifiable {
  public let id: UUID
  public let pattern: String
  public let categoryID: UUID
  public let priority: Int
  public let isEnabled: Bool
  public let createdAt: Date

  public init(
    id: UUID,
    pattern: String,
    categoryID: UUID,
    priority: Int,
    isEnabled: Bool,
    createdAt: Date
  ) {
    self.id = id
    self.pattern = pattern
    self.categoryID = categoryID
    self.priority = priority
    self.isEnabled = isEnabled
    self.createdAt = createdAt
  }
}

/// A value-typed view of a `Transaction` row. Every field the pipeline may
/// read or write; nothing else.
public struct TransactionSnapshot: Sendable, Equatable, Identifiable {
  public var id: UUID
  public var date: Date
  public var descriptionText: String
  public var merchantName: String?
  public var upiKindRaw: String?
  public var counterpartyVPA: String?
  public var normalizedDescription: String
  public var amountMinor: Int
  public var currencyCode: String
  public var directionRaw: String
  public var categoryID: UUID?
  public var categorySourceRaw: String
  public var appliedRuleID: UUID?
  public var accountID: UUID?
  public var sourceRaw: String
  public var sourceRefs: [SourceRef]
  public var mergedCount: Int
  public var needsReview: Bool
  public var dedupeKey: String
  public var createdAt: Date
  public var updatedAt: Date

  // C4. Insert-time facts, same standing as `dedupeKey`: written by
  // `creating(from:)` and never by `MergeResolution`. They are on the snapshot
  // only so the store can round-trip them.
  public var senderDomain: String?
  public var cardFragment: String?
  public var needsReviewReason: NeedsReviewReason?

  public init(
    id: UUID = UUID(),
    date: Date,
    descriptionText: String,
    merchantName: String? = nil,
    upiKindRaw: String? = nil,
    counterpartyVPA: String? = nil,
    normalizedDescription: String,
    amountMinor: Int,
    currencyCode: String = "INR",
    directionRaw: String,
    categoryID: UUID? = nil,
    categorySourceRaw: String = CategorySource.none.rawValue,
    appliedRuleID: UUID? = nil,
    accountID: UUID? = nil,
    sourceRaw: String,
    sourceRefs: [SourceRef] = [],
    mergedCount: Int = 1,
    needsReview: Bool = false,
    dedupeKey: String,
    createdAt: Date,
    updatedAt: Date,
    senderDomain: String? = nil,
    cardFragment: String? = nil,
    needsReviewReason: NeedsReviewReason? = nil
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
    self.needsReviewReason = needsReviewReason
  }

  public var direction: Direction {
    get { Direction(rawValue: directionRaw) ?? .debit }
    set { directionRaw = newValue.rawValue }
  }

  public var categorySource: CategorySource {
    get { CategorySource(rawValue: categorySourceRaw) ?? .none }
    set { categorySourceRaw = newValue.rawValue }
  }

  /// A newly-created row for `derived`, before the rule pass runs.
  static func creating(from derived: DerivedDraft, now: Date) -> TransactionSnapshot {
    let draft = derived.draft
    return TransactionSnapshot(
      date: draft.date,
      descriptionText: draft.descriptionText,
      merchantName: derived.merchantName,
      upiKindRaw: derived.upiKindRaw,
      counterpartyVPA: derived.counterpartyVPA,
      normalizedDescription: derived.normalizedDescription,
      amountMinor: draft.amountMinor,
      currencyCode: draft.currencyCode,
      directionRaw: draft.direction.rawValue,
      categoryID: draft.categoryID,
      categorySourceRaw: draft.categorySource.rawValue,
      appliedRuleID: nil,
      accountID: draft.accountID,
      sourceRaw: draft.source.rawValue,
      sourceRefs: [draft.sourceRef],
      mergedCount: 1,
      needsReview: draft.needsReview,
      dedupeKey: derived.dedupeKey,
      createdAt: now,
      updatedAt: now,
      senderDomain: draft.senderDomain,
      cardFragment: draft.cardFragment,
      needsReviewReason: draft.needsReviewReason
    )
  }

  func hasSourceRef(_ ref: SourceRef) -> Bool {
    sourceRefs.contains { $0.source == ref.source && $0.externalID == ref.externalID }
  }
}

/// One commit batch. `IngestPipeline` builds exactly one of these per public
/// call and hands it to the store in a single `apply`; that is what makes
/// "the observer fires once per batch, not once per row" a structural property
/// rather than a discipline.
public struct CommitPlan: Sendable, Equatable {
  public var inserts: [TransactionSnapshot]
  public var updates: [TransactionSnapshot]
  public var deletes: [UUID]
  public var affectedCategoryIDs: Set<UUID>

  public init(
    inserts: [TransactionSnapshot] = [],
    updates: [TransactionSnapshot] = [],
    deletes: [UUID] = [],
    affectedCategoryIDs: Set<UUID> = []
  ) {
    self.inserts = inserts
    self.updates = updates
    self.deletes = deletes
    self.affectedCategoryIDs = affectedCategoryIDs
  }

  public var isEmpty: Bool {
    inserts.isEmpty && updates.isEmpty && deletes.isEmpty
  }
}

public struct IngestBatchResult: Sendable, Equatable {
  public let created: Int
  public let merged: Int
  public let flagged: Int

  public init(created: Int, merged: Int, flagged: Int) {
    self.created = created
    self.merged = merged
    self.flagged = flagged
  }

  public static let empty = IngestBatchResult(created: 0, merged: 0, flagged: 0)
}

/// Result of the R5 CloudKit reconcile pass.
public struct ReconcileResult: Sendable, Equatable {
  public let groupsCollapsed: Int
  public let rowsRemoved: Int

  public init(groupsCollapsed: Int, rowsRemoved: Int) {
    self.groupsCollapsed = groupsCollapsed
    self.rowsRemoved = rowsRemoved
  }

  public static let empty = ReconcileResult(groupsCollapsed: 0, rowsRemoved: 0)
}
