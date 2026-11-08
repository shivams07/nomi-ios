import Foundation

/// A value view of a row, for the transfer rules. Mapped from `Transaction` by
/// the two editors, and by the T2 detector. No defaults: a field that is not
/// passed is a guess, and this type exists so nothing is guessed.
public struct TransferLeg: Sendable, Equatable {
  public let id: UUID
  public let date: Date
  public let amountMinor: Int
  public let currencyCode: String
  public let directionRaw: String
  public let accountID: UUID?
  public let transferGroupID: UUID?
  public let transferSourceRaw: String?

  public init(
    id: UUID,
    date: Date,
    amountMinor: Int,
    currencyCode: String,
    directionRaw: String,
    accountID: UUID?,
    transferGroupID: UUID?,
    transferSourceRaw: String?
  ) {
    self.id = id
    self.date = date
    self.amountMinor = amountMinor
    self.currencyCode = currencyCode
    self.directionRaw = directionRaw
    self.accountID = accountID
    self.transferGroupID = transferGroupID
    self.transferSourceRaw = transferSourceRaw
  }
}

/// A row's transfer pair, `(transferGroupID, transferSourceRaw)` (DEC-05
/// Amendment 3). Compared as a whole: a pipeline write is judged on the pair,
/// never on one field.
public struct TransferPair: Sendable, Equatable {
  public let groupID: UUID?
  public let sourceRaw: String?

  public init(groupID: UUID?, sourceRaw: String?) {
    self.groupID = groupID
    self.sourceRaw = sourceRaw
  }
}

/// What a pair means to this build. `unrecognized` covers every pair this build
/// never writes, including the values a newer build may add.
public enum TransferPairState: Sendable, Equatable {
  case unmarked, auto, manual, rejected, unrecognized
}

/// The one copy of the transfer rules (DEC-05, Amendments 1 and 3). Both
/// `setTransfer` conformers and the T2 detector call it. Pure: the calendar is
/// passed, never read from the environment.
public enum TransferRules {
  /// A match is at most this many calendar days apart (absolute day difference
  /// of `startOfDay` in the calendar passed in).
  public static let windowDays = 3

  /// Classifies a pair. Exactly four pairs are recognised: unmarked `(nil, nil)`,
  /// `(id, auto)`, `(id, manual)` and `(nil, rejected)`. Every other pair is
  /// `unrecognized`, including `(id, nil)`, `(id, rejected)`, `(nil, auto)` and
  /// `(nil, manual)`, which this build never writes.
  public static func state(_ pair: TransferPair) -> TransferPairState {
    let auto = TransferSource.auto.rawValue
    let manual = TransferSource.manual.rawValue
    let rejected = TransferSource.rejected.rawValue
    if pair.groupID == nil && pair.sourceRaw == nil { return .unmarked }
    if pair.groupID != nil && pair.sourceRaw == auto { return .auto }
    if pair.groupID != nil && pair.sourceRaw == manual { return .manual }
    if pair.groupID == nil && pair.sourceRaw == rejected { return .rejected }
    return .unrecognized
  }

  /// Two legs of one transfer: different rows, both INR, one debit and one
  /// credit, equal `amountMinor`, both accounts non-nil and different, and
  /// within `windowDays`. Says nothing about either row's transfer state; see
  /// `isFree` for that.
  public static func matches(_ a: TransferLeg, _ b: TransferLeg, calendar: Calendar) -> Bool {
    guard a.id != b.id else { return false }
    guard a.currencyCode == "INR", b.currencyCode == "INR" else { return false }
    guard a.amountMinor == b.amountMinor else { return false }

    let debit = Direction.debit.rawValue
    let credit = Direction.credit.rawValue
    let oppositeDirections =
      (a.directionRaw == debit && b.directionRaw == credit)
      || (a.directionRaw == credit && b.directionRaw == debit)
    guard oppositeDirections else { return false }

    guard let accountA = a.accountID, let accountB = b.accountID, accountA != accountB else {
      return false
    }
    return dayDistance(a.date, b.date, calendar: calendar) <= windowDays
  }

  /// A row a match may claim: its pair is unmarked, and nothing else. A
  /// `rejected` row is one the user said is not a transfer, and an unrecognised
  /// row is one this build cannot read; neither is claimed by another row's
  /// mark (DEC-05 Amendment 3, U4).
  public static func isFree(_ leg: TransferLeg) -> Bool {
    state(TransferPair(groupID: leg.transferGroupID, sourceRaw: leg.transferSourceRaw)) == .unmarked
  }

  /// `matches` for two free legs. The detector's base test (T2).
  public static func isEligiblePair(_ a: TransferLeg, _ b: TransferLeg, calendar: Calendar) -> Bool {
    matches(a, b, calendar: calendar) && isFree(a) && isFree(b)
  }

  /// The id of the one free candidate that matches `row`. `nil` for zero or for
  /// two or more: an ambiguous match marks nothing. `row`'s own transfer state
  /// is not tested, because re-marking a rejected row is the user's right.
  public static func manualPartner(
    for row: TransferLeg,
    among candidates: [TransferLeg],
    calendar: Calendar
  ) -> UUID? {
    let found = candidates.filter { matches(row, $0, calendar: calendar) && isFree($0) }
    guard found.count == 1 else { return nil }
    return found[0].id
  }

  /// Whether a pipeline write may change a row's transfer pair (DEC-05
  /// Amendment 3, rule C). `read` is the pair the pipeline read from the store
  /// with the snapshot. Nothing is written without it, and nothing is written
  /// if the row has changed since, so a stale snapshot never undoes or
  /// re-creates a decision. Then, by the state of `current`:
  /// - unmarked: any recognised incoming pair;
  /// - auto: auto, manual or rejected;
  /// - manual, rejected, unrecognized: nothing.
  public static func pipelineMayWrite(
    read: TransferPair?,
    current: TransferPair,
    incoming: TransferPair
  ) -> Bool {
    guard let read, read == current else { return false }
    let incomingState = state(incoming)
    switch state(current) {
    case .unmarked:
      return incomingState != .unrecognized
    case .auto:
      return [TransferPairState.auto, .manual, .rejected].contains(incomingState)
    case .manual, .rejected, .unrecognized:
      return false
    }
  }

  /// The survivor's pair after a reconcile collapse (DEC-05 Amendment 3, rule
  /// U3 and A-05 item 17). Returns `nil` when the survivor or any other row
  /// holds an unrecognised pair: the group is then left alone. Otherwise, in
  /// this order: survivor `manual` or `rejected` keeps its own; else any other
  /// `rejected` gives `(nil, rejected)`; else the first other `manual`; else
  /// survivor `auto` keeps its own; else the first other `auto`; else unmarked.
  /// `others` is in the caller's order.
  public static func collapsedTransferFields(
    survivor: TransferPair,
    others: [TransferPair]
  ) -> TransferPair? {
    if state(survivor) == .unrecognized || others.contains(where: { state($0) == .unrecognized }) {
      return nil
    }
    if state(survivor) == .manual || state(survivor) == .rejected { return survivor }
    if others.contains(where: { state($0) == .rejected }) {
      return TransferPair(groupID: nil, sourceRaw: TransferSource.rejected.rawValue)
    }
    if let firstManual = others.first(where: { state($0) == .manual }) { return firstManual }
    if state(survivor) == .auto { return survivor }
    if let firstAuto = others.first(where: { state($0) == .auto }) { return firstAuto }
    return TransferPair(groupID: nil, sourceRaw: nil)
  }

  /// Whole calendar days between the two dates' start-of-day, absolute.
  private static func dayDistance(_ a: Date, _ b: Date, calendar: Calendar) -> Int {
    let days = calendar.dateComponents(
      [.day],
      from: calendar.startOfDay(for: a),
      to: calendar.startOfDay(for: b)
    ).day ?? Int.max
    return abs(days)
  }
}
