import Foundation

/// The conditions a rule requires *in addition to* its pattern (§W2-5).
///
/// Every field is optional and every unset field is "don't care", so
/// `RuleScope.any` — all four unset — is exactly the behaviour rules had
/// before this type existed. That is what makes the four columns on `Rule`
/// additive: a row written before scoping reads back as `.any` and matches
/// what it always matched.
///
/// A set field is an AND, never an OR. Direction, account and the amount
/// bounds all have to admit a row before the pattern is even consulted.
public struct RuleScope: Sendable, Equatable, Codable {

  /// Debits only, credits only, or either when `nil`.
  public var direction: Direction?

  /// One account, or any account when `nil`.
  ///
  /// A row with no `accountID` is admitted only by `nil` here. An unowned row
  /// cannot be said to be in the account the user picked, and guessing "close
  /// enough" is how a rule scoped to one card starts firing on rows that
  /// belong to another.
  public var accountID: UUID?

  /// Inclusive bounds, in minor units, on `Transaction.amountMinor`.
  ///
  /// The ledger stores amounts as magnitudes — `RowMapper` normalises a signed
  /// CSV amount with `abs` and puts the sign in `direction` — so a bound is a
  /// magnitude too, and "debits over ₹1000" is `direction: .debit` plus
  /// `minAmountMinor: 100_000`, not a negative bound.
  public var minAmountMinor: Int?
  public var maxAmountMinor: Int?

  public static let any = RuleScope()

  public init(
    direction: Direction? = nil,
    accountID: UUID? = nil,
    minAmountMinor: Int? = nil,
    maxAmountMinor: Int? = nil
  ) {
    self.direction = direction
    self.accountID = accountID
    self.minAmountMinor = minAmountMinor
    self.maxAmountMinor = maxAmountMinor
  }

  /// No condition set: this rule is decided by its pattern alone.
  public var isAny: Bool { self == .any }

  /// `false` when the bounds cross, which admits nothing at all.
  ///
  /// Not enforced here — a `RuleScope` is a value and refusing to hold one
  /// would push the check into every construction site. The editor gates on it
  /// (W2-M4) and `admits` answers honestly in the meantime: a crossed range
  /// rejects every row, which is what the user asked for even though it is
  /// unlikely to be what they meant.
  public var isValidRange: Bool {
    guard let low = minAmountMinor, let high = maxAmountMinor else { return true }
    return low <= high
  }

  /// Whether a row's facts satisfy every condition that is set.
  ///
  /// Takes the three facts rather than a row type on purpose: the pipeline's
  /// `TransactionSnapshot` lives in `NomiIngest`, which sits above this
  /// package, and `Transaction` is a `@Model` that no test in this repo can
  /// construct under `swift test`. Primitives keep the decision runnable.
  public func admits(direction rowDirection: Direction, accountID rowAccountID: UUID?, amountMinor: Int) -> Bool {
    if let direction, direction != rowDirection { return false }
    if let accountID, accountID != rowAccountID { return false }
    if let minAmountMinor, amountMinor < minAmountMinor { return false }
    if let maxAmountMinor, amountMinor > maxAmountMinor { return false }
    return true
  }
}
