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

/// The one copy of the transfer match rule (DEC-05, Amendment 1). Both
/// `setTransfer` conformers and the T2 detector call it. Pure: the calendar is
/// passed, never read from the environment.
public enum TransferRules {
  /// A match is at most this many calendar days apart (absolute day difference
  /// of `startOfDay` in the calendar passed in).
  public static let windowDays = 3

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

  /// A row a match may claim: not grouped, and not `rejected`. A rejected row
  /// is one the user said is not a transfer, so nothing pairs it on its own
  /// account's behalf.
  public static func isFree(_ leg: TransferLeg) -> Bool {
    leg.transferGroupID == nil && leg.transferSourceRaw != TransferSource.rejected.rawValue
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

  /// Whether a pipeline write may set a row's transfer pair (A-05 item 16).
  /// From `nil` always. From `auto` only to `auto`, `manual` or `rejected`.
  /// From `manual`, `rejected` or an unknown value, never. So a snapshot read
  /// before a user's mark cannot undo it, and `nil` cannot erase an `auto` mark.
  public static func pipelineMayWrite(currentRaw: String?, incomingRaw: String?) -> Bool {
    guard let currentRaw else { return true }
    guard currentRaw == TransferSource.auto.rawValue else { return false }
    guard let incomingRaw else { return false }
    let allowed: [String] = [TransferSource.auto, .manual, .rejected].map(\.rawValue)
    return allowed.contains(incomingRaw)
  }

  /// The survivor's transfer pair after a reconcile collapse (A-05 item 17), in
  /// this order: survivor `manual` or `rejected` keeps its own; else any other
  /// `rejected` gives `(nil, rejected)`; else the first other `manual`; else
  /// survivor `auto` keeps its own; else the first other `auto`; else `(nil, nil)`.
  /// `others` is in the caller's order.
  public static func collapsedTransferFields(
    survivor: (UUID?, String?),
    others: [(UUID?, String?)]
  ) -> (UUID?, String?) {
    let manual = TransferSource.manual.rawValue
    let rejected = TransferSource.rejected.rawValue
    let auto = TransferSource.auto.rawValue

    if survivor.1 == manual || survivor.1 == rejected { return survivor }
    if others.contains(where: { $0.1 == rejected }) { return (nil, rejected) }
    if let firstManual = others.first(where: { $0.1 == manual }) { return firstManual }
    if survivor.1 == auto { return survivor }
    if let firstAuto = others.first(where: { $0.1 == auto }) { return firstAuto }
    return (nil, nil)
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
