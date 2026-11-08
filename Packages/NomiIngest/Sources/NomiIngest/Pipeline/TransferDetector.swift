import Foundation
import NomiCore

/// The account facts the detector reads for one account: its kind, and the last
/// four digits the account is known by. The store supplies them; the detector
/// never reads a store, so it stays a pure function over values (DEC-05).
public struct TransferAccount: Sendable, Equatable {
  public let kind: AccountKind
  public let lastFour: String

  public init(kind: AccountKind, lastFour: String) {
    self.kind = kind
    self.lastFour = lastFour
  }

  /// One entry per account id (TR1). CloudKit has no unique constraint, so one
  /// id can arrive twice. Two entries with the same facts give those facts. Two
  /// entries that disagree give `.bank` with no digits, so a disputed account is
  /// never treated as a card. Never `Dictionary(uniqueKeysWithValues:)`, which
  /// traps on a duplicate.
  public static func byID(_ entries: [(UUID, TransferAccount)]) -> [UUID: TransferAccount] {
    var grouped: [UUID: [TransferAccount]] = [:]
    for (id, facts) in entries {
      grouped[id, default: []].append(facts)
    }
    var resolved: [UUID: TransferAccount] = [:]
    for (id, all) in grouped {
      let first = all[0]
      resolved[id] = all.allSatisfy { $0 == first }
        ? first
        : TransferAccount(kind: .bank, lastFour: "")
    }
    return resolved
  }
}

/// One leg of a matched pair, to be written as an `auto` mark. `groupID` is
/// shared by both legs (`TransferGroupID.make(id, partnerID)`), so one pair is
/// always two marks. A mark is written only through `TransferPairWrite`, never
/// on its own.
public struct TransferMark: Sendable, Equatable {
  public let id: UUID
  public let partnerID: UUID
  public let groupID: UUID

  public init(id: UUID, partnerID: UUID, groupID: UUID) {
    self.id = id
    self.partnerID = partnerID
    self.groupID = groupID
  }

  /// The pair to write, `(groupID, "auto")`.
  public var pair: TransferPair {
    TransferPair(groupID: groupID, sourceRaw: TransferSource.auto.rawValue)
  }
}

/// A leg as the store read it, or as it is now: the three facts a pair write
/// depends on. The pair is `nil` only for a snapshot not read from the store.
public struct TransferLegState: Sendable, Equatable {
  public let id: UUID
  public let accountID: UUID?
  public let pair: TransferPair?

  public init(id: UUID, accountID: UUID?, pair: TransferPair?) {
    self.id = id
    self.accountID = accountID
    self.pair = pair
  }
}

/// A complete pair to write: both legs and the pair both take (TR4). `first` is
/// the leg with the smaller `uuidString`, so one pair has one shape.
public struct TransferPairWrite: Sendable, Equatable {
  public let first: TransferLegState
  public let second: TransferLegState
  public let pair: TransferPair

  public init(first: TransferLegState, second: TransferLegState, pair: TransferPair) {
    self.first = first
    self.second = second
    self.pair = pair
  }

  /// Whether this write may still land, given both legs now (TR4). True only if
  /// the ids still match, the pair is an `auto` pair, and for each leg: the
  /// account it was read with is still the account (and was not nil), the
  /// current pair is present, and `TransferRules.pipelineMayWrite` allows the
  /// change from the pair as read. Every leg must pass; a single failing leg
  /// refuses the whole pair.
  public func mayWrite(firstNow: TransferLegState, secondNow: TransferLegState) -> Bool {
    guard first.id != second.id else { return false }
    guard firstNow.id == first.id, secondNow.id == second.id else { return false }
    guard TransferRules.state(pair) == .auto else { return false }
    return Self.legMayWrite(read: first, now: firstNow, incoming: pair)
      && Self.legMayWrite(read: second, now: secondNow, incoming: pair)
  }

  private static func legMayWrite(read: TransferLegState, now: TransferLegState, incoming: TransferPair) -> Bool {
    guard let readAccount = read.accountID, now.accountID == readAccount else { return false }
    guard let current = now.pair else { return false }
    return TransferRules.pipelineMayWrite(read: read.pair, current: current, incoming: incoming)
  }

  /// The complete pairs among `marks` that a touched row belongs to (TR4). A
  /// group is kept only if it has exactly two marks that name each other, both
  /// ids were read, and at least one id is in `touching`. So a pair that had no
  /// seed in this batch is not written by this call. Sorted by `first`.
  public static func writes(
    from marks: [TransferMark],
    readStates: [UUID: TransferLegState],
    touching: Set<UUID>
  ) -> [TransferPairWrite] {
    let byGroup = Dictionary(grouping: marks, by: \.groupID)
    var result: [TransferPairWrite] = []
    for (groupID, group) in byGroup {
      guard group.count == 2 else { continue }
      let lhs = group[0]
      let rhs = group[1]
      guard lhs.partnerID == rhs.id, rhs.partnerID == lhs.id else { continue }
      guard let lhsState = readStates[lhs.id], let rhsState = readStates[rhs.id] else { continue }
      guard touching.contains(lhs.id) || touching.contains(rhs.id) else { continue }
      let (first, second) = lhs.id.uuidString < rhs.id.uuidString
        ? (lhsState, rhsState)
        : (rhsState, lhsState)
      result.append(TransferPairWrite(
        first: first,
        second: second,
        pair: TransferPair(groupID: groupID, sourceRaw: TransferSource.auto.rawValue)
      ))
    }
    return result.sorted { $0.first.id.uuidString < $1.first.id.uuidString }
  }

  /// The writes that may land (TR4). A write is dropped if either leg appears in
  /// another write of the same call, if a leg is missing from `now`, or if its
  /// `mayWrite` is false. Pure, so the one decision serves both callers.
  public static func accepted(
    _ writes: [TransferPairWrite],
    now: [UUID: TransferLegState]
  ) -> [TransferPairWrite] {
    var appearances: [UUID: Int] = [:]
    for write in writes {
      appearances[write.first.id, default: 0] += 1
      appearances[write.second.id, default: 0] += 1
    }
    return writes.filter { write in
      guard appearances[write.first.id] == 1, appearances[write.second.id] == 1 else { return false }
      guard let firstNow = now[write.first.id], let secondNow = now[write.second.id] else { return false }
      return write.mayWrite(firstNow: firstNow, secondNow: secondNow)
    }
  }
}

/// The automatic transfer detector (DEC-05, "Detector").
///
/// Marks a pair only when every condition holds:
/// - the base test, `TransferRules.isEligiblePair` (INR, one debit and one
///   credit, equal amount, different non-nil accounts, within three calendar
///   days, both legs unmarked);
/// - a unique match on both sides (TR3). The competitors of a leg are every row
///   that `TransferRules.matches` it and whose pair is unmarked or unrecognised.
///   An unrecognised row competes: a row this build cannot read still counts as
///   a candidate, so it blocks a mark. Auto, manual and rejected rows do not
///   compete: each is already decided. Uniqueness is counted before, and
///   independently of, the card and narration conditions below;
/// - the credit leg's account is a card (`AccountKind.card`);
/// - narration evidence on at least one leg (see `TransferNarration`).
///
/// `rows` must hold every row that could compete for a leg in it: all rows of
/// the same amount, in both directions, inside the window the caller read. A
/// row missing from `rows` can make a match look unique when it is not, and the
/// detector cannot tell.
public enum TransferDetector {
  /// The marks for every matched pair among `rows`, sorted by leg id. A row id
  /// that appears twice is the same row: the first occurrence is used.
  public static func detect(
    rows: [TransactionSnapshot],
    accounts: [UUID: TransferAccount],
    calendar: Calendar
  ) -> [TransferMark] {
    var seen = Set<UUID>()
    let legs = rows.filter { seen.insert($0.id).inserted }
    let byID = Dictionary(uniqueKeysWithValues: legs.map { ($0.id, $0) })

    // Matching needs equal amounts, so the pairwise scan runs inside each amount.
    var competitors: [UUID: [UUID]] = [:]
    for group in Dictionary(grouping: legs, by: \.amountMinor).values where group.count > 1 {
      for lhs in group {
        for rhs in group where lhs.id != rhs.id {
          guard TransferRules.matches(lhs.transferLeg, rhs.transferLeg, calendar: calendar) else { continue }
          switch TransferRules.state(rhs.transferPair) {
          case .unmarked, .unrecognized:
            competitors[lhs.id, default: []].append(rhs.id)
          case .auto, .manual, .rejected:
            continue
          }
        }
      }
    }

    var marks: [TransferMark] = []
    for credit in legs where credit.directionRaw == Direction.credit.rawValue {
      guard
        TransferRules.state(credit.transferPair) == .unmarked,
        let debitIDs = competitors[credit.id], debitIDs.count == 1,
        let debitID = debitIDs.first, let debit = byID[debitID],
        TransferRules.state(debit.transferPair) == .unmarked,
        competitors[debitID] == [credit.id],
        TransferRules.isEligiblePair(credit.transferLeg, debit.transferLeg, calendar: calendar),
        let cardID = credit.accountID, let card = accounts[cardID], card.kind == .card,
        TransferNarration.evidence(credit: credit.descriptionText, debit: debit.descriptionText, lastFour: card.lastFour)
      else { continue }

      let group = TransferGroupID.make(credit.id, debit.id)
      marks.append(TransferMark(id: credit.id, partnerID: debit.id, groupID: group))
      marks.append(TransferMark(id: debit.id, partnerID: credit.id, groupID: group))
    }
    return marks.sorted { $0.id.uuidString < $1.id.uuidString }
  }
}

/// The narration evidence the detector requires (DEC-05). Pure string work,
/// case-insensitive. The phrases are seeds, settled by the fixtures in
/// `TransferDetectorTests` and not measured from real mail (decisions file,
/// assumption 5).
enum TransferNarration {
  /// On the credit leg: the card side reads as a payment received.
  static let creditPhrases = ["payment received", "thank you for payment", "bill payment", "cc payment"]

  /// On the debit leg: the bank side names a card.
  static let debitPhrases = ["credit card", "cc payment", "card bill", "card payment"]

  /// Evidence on at least one leg: the credit leg reads as a payment, or the
  /// debit leg names a card by phrase or by the card's last four digits.
  static func evidence(credit: String, debit: String, lastFour: String) -> Bool {
    creditReadsAsPayment(credit) || debitNamesCard(debit, lastFour: lastFour)
  }

  static func creditReadsAsPayment(_ text: String) -> Bool {
    contains(text, creditPhrases)
  }

  static func debitNamesCard(_ text: String, lastFour: String) -> Bool {
    if contains(text, debitPhrases) { return true }
    return digitTokens(text).contains(lastFour)
  }

  private static func contains(_ text: String, _ phrases: [String]) -> Bool {
    let lower = text.lowercased()
    return phrases.contains { lower.contains($0) }
  }

  /// Whole tokens of exactly four ASCII digits. A token is a run of letters and
  /// digits, so "4471X" and "XX4471" are not tokens equal to "4471": the match
  /// is strict on purpose. A false negative leaves the spend counted, which is
  /// the visible failure DEC-05 prefers.
  private static func digitTokens(_ text: String) -> Set<String> {
    let runs = text.components(separatedBy: CharacterSet.alphanumerics.inverted)
    return Set(runs.filter { run in
      run.count == 4 && run.allSatisfy { $0.isASCII && $0.isNumber }
    })
  }
}

extension TransactionSnapshot {
  /// The value view `TransferRules` reads. Mirrors `Transaction.transferLeg`.
  fileprivate var transferLeg: TransferLeg {
    TransferLeg(
      id: id,
      date: date,
      amountMinor: amountMinor,
      currencyCode: currencyCode,
      directionRaw: directionRaw,
      accountID: accountID,
      transferGroupID: transferGroupID,
      transferSourceRaw: transferSourceRaw
    )
  }
}
