import Foundation
import NomiCore

/// §1.5's seam, verbatim. Two protocols, not one, and the split is the point.
///
/// An Apple Foundation Models implementation could only ever be an
/// `ExtractionEnricher`, so it is *structurally incapable* of touching `date`,
/// `amountMinor` or `normalizedDescription` — the fields that feed `dedupeKey`.
/// The rule lives in the type system rather than in a review checklist.
///
/// There is no `import FoundationModels` anywhere in this codebase and there
/// must not be at MVP (§1.5, R12).
public protocol TransactionExtractor: Sendable {
  /// Canonical extraction. MUST be deterministic — identical input bytes produce
  /// identical output on every device, every OS version, forever. Feeds
  /// `dedupeKey`.
  ///
  /// See `MailDate.bankTimeZone` for the one place that determinism took a
  /// deliberate decision rather than falling out for free.
  func extract(_ message: MailMessage) throws -> TransactionDraft?
}

public protocol ExtractionEnricher: Sendable {
  /// Optional, best-effort, may be absent. Runs AFTER `extract()`, never instead
  /// of it, and may only produce suggestions for fields that do NOT feed
  /// `dedupeKey`. A nil return is always acceptable.
  func enrich(_ draft: TransactionDraft, _ message: MailMessage) async -> DraftEnrichment?
}

public struct DraftEnrichment: Sendable, Equatable {
  public let suggestedCategoryID: UUID?
  public let suggestedAccountID: UUID?

  public init(suggestedCategoryID: UUID?, suggestedAccountID: UUID?) {
    self.suggestedCategoryID = suggestedCategoryID
    self.suggestedAccountID = suggestedAccountID
  }
}

/// Which layer produced a draft. Not on `TransactionExtractor` because the
/// protocol is the FM seam and must stay minimal; this is the concrete
/// extractor's own reporting channel, and it is what feeds `packMatched` /
/// `heuristicMatched` — the two counters the whole Foundation Models decision
/// turns on (§1.5).
public enum ExtractionLayer: String, Sendable, Equatable {
  case pack
  case heuristic
}

public struct ExtractionOutcome: Sendable, Equatable {
  public let draft: TransactionDraft?
  public let layer: ExtractionLayer?
  /// Set when the message was a genuine candidate — right domain, an amount, a
  /// verb — but no layer could read it. §1.4's safety net: it becomes ONE
  /// `needsReview` row showing the raw narration, not a silent miss.
  public let wasUnparseableCandidate: Bool

  public init(draft: TransactionDraft?, layer: ExtractionLayer?, wasUnparseableCandidate: Bool) {
    self.draft = draft
    self.layer = layer
    self.wasUnparseableCandidate = wasUnparseableCandidate
  }

  static let notACandidate = ExtractionOutcome(
    draft: nil, layer: nil, wasUnparseableCandidate: false)
}

/// `(senderDomain, cardFragment) -> accountID`, learned once and reused (§1.2).
///
/// U2 does not own the `AccountBinding` rows — they are `@Model` types in
/// NomiCore and only U8 has a `ModelContext`. This is the seam U8 implements.
/// A resolver that returns nil is correct and normal: §1.2 says leave
/// `accountID` nil and flag for review rather than guess, because a wrong
/// account is *silently* wrong.
public protocol AccountBindingResolving: Sendable {
  func accountID(senderDomain: String, cardFragment: String) -> UUID?
}

/// The default before the user has taught it anything.
public struct NoAccountBindings: AccountBindingResolving {
  public init() {}
  public func accountID(senderDomain: String, cardFragment: String) -> UUID? { nil }
}
