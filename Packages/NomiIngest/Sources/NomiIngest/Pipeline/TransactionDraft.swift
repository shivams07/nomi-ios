import Foundation
import NomiCore

/// The pipeline's only input. `Mail/` (U2) and `File/` (U3) produce these;
/// nothing outside `Pipeline/` may write a `Transaction`.
///
/// Note what is *absent*: `normalizedDescription` and `dedupeKey`. An ingester
/// cannot supply them because the pipeline is their sole deriver — see
/// `DraftDerivation`. The three UPI fields below exist only so the pipeline can
/// assert an ingester left them alone (§2.4); `DraftDerivation.derive` ignores
/// whatever they hold and re-derives from `descriptionText`.
public struct TransactionDraft: Sendable, Equatable {
  /// The transaction date as the source reported it. Time-of-day is not
  /// significant — the dedupe key uses start-of-day.
  public var date: Date

  /// Raw narration, verbatim. NEVER rewritten, by this unit or any other.
  public var descriptionText: String

  /// Paise. `Int` by contract — a `Double` here is a rejected PR (R9).
  public var amountMinor: Int
  public var direction: Direction
  public var currencyCode: String

  /// `nil` when the source could not identify the account (§1.2).
  public var accountID: UUID?

  public var source: IngestSource

  /// IMAP message UID, or file signature + row index, or the reference column
  /// when the CSV carried one. Together with `source` this identifies the
  /// contributor, and re-ingesting the same contributor is a true no-op.
  public var externalID: String
  public var capturedAt: Date

  /// Set by the ingester when extraction was uncertain (a Layer-2 email, an
  /// unparseable candidate). The pipeline only ever ORs more reasons on top.
  public var needsReview: Bool

  /// Manual entry only. An ingested draft leaves these at `nil` / `.none` and
  /// lets the rule pass decide.
  public var categoryID: UUID?
  public var categorySource: CategorySource

  // §2.4 — display-only, derived by the pipeline. An ingester that fills these
  // in is the bug this field exists to catch.
  public var merchantName: String?
  public var upiKindRaw: String?
  public var counterpartyVPA: String?

  public init(
    date: Date,
    descriptionText: String,
    amountMinor: Int,
    direction: Direction,
    currencyCode: String = "INR",
    accountID: UUID? = nil,
    source: IngestSource,
    externalID: String,
    capturedAt: Date = Date(),
    needsReview: Bool = false,
    categoryID: UUID? = nil,
    categorySource: CategorySource = .none,
    merchantName: String? = nil,
    upiKindRaw: String? = nil,
    counterpartyVPA: String? = nil
  ) {
    self.date = date
    self.descriptionText = descriptionText
    self.amountMinor = amountMinor
    self.direction = direction
    self.currencyCode = currencyCode
    self.accountID = accountID
    self.source = source
    self.externalID = externalID
    self.capturedAt = capturedAt
    self.needsReview = needsReview
    self.categoryID = categoryID
    self.categorySource = categorySource
    self.merchantName = merchantName
    self.upiKindRaw = upiKindRaw
    self.counterpartyVPA = counterpartyVPA
  }

  public var sourceRef: SourceRef {
    SourceRef(source: source, externalID: externalID, capturedAt: capturedAt)
  }
}
