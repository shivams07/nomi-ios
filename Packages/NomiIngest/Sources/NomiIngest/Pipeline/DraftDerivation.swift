import Foundation
import NomiCore

/// A draft plus everything the pipeline derived from it. Construct only via
/// `DraftDerivation.derive`.
public struct DerivedDraft: Sendable, Equatable {
  public let draft: TransactionDraft

  /// From `draft.descriptionText` ONLY. Never from `merchantName`.
  public let normalizedDescription: String

  /// From `date`, `amountMinor`, `directionRaw` and `normalizedDescription`.
  /// The three UPI fields are provably absent from this — see
  /// `DedupeKeyIndependenceTests`.
  public let dedupeKey: String

  public let merchantName: String?
  public let upiKindRaw: String?
  public let counterpartyVPA: String?
}

/// An ingester filled in a field it does not own (§2.4).
public enum DraftDerivationViolation: String, Sendable, Equatable, CaseIterable {
  case merchantNamePreset
  case upiKindRawPreset
  case counterpartyVPAPreset
}

/// The SOLE deriver of `normalizedDescription`, `dedupeKey`, `merchantName`,
/// `upiKindRaw` and `counterpartyVPA` (§2.4). Ingesters never parse.
public enum DraftDerivation {

  /// Split out from `derive` so the rule can be tested. `derive` traps on a
  /// violation in debug builds; a test cannot catch a trap, so it asserts on
  /// this instead.
  public static func violations(in draft: TransactionDraft) -> [DraftDerivationViolation] {
    var found: [DraftDerivationViolation] = []
    if draft.merchantName != nil { found.append(.merchantNamePreset) }
    if draft.upiKindRaw != nil { found.append(.upiKindRawPreset) }
    if draft.counterpartyVPA != nil { found.append(.counterpartyVPAPreset) }
    return found
  }

  public static func derive(_ draft: TransactionDraft, calendar: Calendar = .current) -> DerivedDraft {
    assert(
      violations(in: draft).isEmpty,
      "Ingester pre-filled a pipeline-derived field: \(violations(in: draft)). See design §2.4."
    )

    let normalized = normalizeDescription(draft.descriptionText)
    let key = makeDedupeKey(
      date: draft.date,
      amountMinor: draft.amountMinor,
      directionRaw: draft.direction.rawValue,
      normalizedDescription: normalized,
      calendar: calendar
    )

    // Release builds do not trap, so re-derive rather than trust the draft.
    let upi = UPINarration.parse(draft.descriptionText)

    return DerivedDraft(
      draft: draft,
      normalizedDescription: normalized,
      dedupeKey: key,
      merchantName: upi?.merchantName,
      upiKindRaw: upi?.upiKindRaw,
      counterpartyVPA: upi?.counterpartyVPA
    )
  }
}
