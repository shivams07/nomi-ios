import Foundation
import NomiCore

/// `NomiFormatters.amountString` always strips the sign (by design — most
/// callers add their own `+`/`` based on transaction direction, see
/// `TransactionRow`). A tracked balance has no direction to hang a sign off
/// of and can go negative on an overdrawn account, so this is the one place
/// that needs its own `-` prefix or a negative balance would render
/// indistinguishably from a positive one.
enum TrackedBalanceText {
  static func string(minor: Int) -> String {
    let sign = minor < 0 ? "-" : ""
    return sign + NomiFormatters.amountString(minor: minor)
  }
}

/// The "since <trackingSince>" caption beneath the tracked balance. `nil`
/// for an account with zero transactions (`InsightsStore.accountSummaries`
/// derives `trackingSince` from the earliest transaction date, so there is
/// nothing to date yet) — the caller omits the line entirely rather than
/// rendering "since" with no date.
enum TrackedBalanceCaption {
  static func sinceText(_ date: Date?) -> String? {
    guard let date else { return nil }
    return "since \(NomiFormatters.dayMonthYear.string(from: date))"
  }
}

/// Splits summaries into the always-visible list and the collapsed archived
/// section — pulled out so "archived accounts move to a collapsed section,
/// not out of existence" is a policy the tests can check directly.
enum AccountSectioning {
  static func active(_ summaries: [AccountSummary]) -> [AccountSummary] {
    summaries.filter { !$0.isArchived }
  }

  static func archived(_ summaries: [AccountSummary]) -> [AccountSummary] {
    summaries.filter { $0.isArchived }
  }
}

/// Fixed kind choices for account creation. `Account.kindRaw` is a `String`,
/// not an enum — introducing `AccountKind` in `NomiCore` would put
/// `Contracts/Types.swift` in this unit for no gain, so the choices live
/// here, the way `PaletteSlotOptions` does for categories.
/// The picker's choices, derived from the model rather than retyped beside it.
/// A hand-written list here is a list that silently disagrees with what
/// `SwiftDataAccountStore.create` will now accept.
enum AccountKindOptions {
  static let all: [String] = AccountKind.allCases.map(\.rawValue)
  static let defaultKind = AccountKind.bank.rawValue
}

/// `lastFour` is exactly four digits or empty — never partial. That rule is
/// not cosmetic: `lastFour` is the `cardFragment` half of the
/// `AccountBinding` key another unit relies on, so a value like "471" or
/// "•• 4471" would silently break mail auto-resolution later with no visible
/// symptom. Shared by `AccountCreateFormGate` and `AccountEditFormGate` so
/// the two forms can't drift onto two different definitions of "valid".
enum AccountLastFourGate {
  static func isValid(_ lastFour: String) -> Bool {
    lastFour.isEmpty || (lastFour.count == 4 && lastFour.allSatisfy { $0.isASCII && $0.isNumber })
  }
}

/// Gates account creation: `displayName` is required and non-blank, same
/// rule `AccountEditFormGate` applies to the edit sheet.
enum AccountCreateFormGate {
  static func isValid(displayName: String, lastFour: String) -> Bool {
    let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else { return false }
    return AccountLastFourGate.isValid(lastFour)
  }
}

/// The opening-balance `TextField`'s two directions: seeding editable plain
/// text from the stored value, and parsing typed text back into
/// `AccountStore.update`'s `openingBalanceMinor: Int?` — which, per that
/// method's own doc comment, treats `nil` as "clear the value", not "leave it
/// alone". An account can legitimately already be overdrawn the day this app
/// first sees it, so unlike `EntryAmount` (which rejects zero and negative —
/// this field cannot reuse it) a leading `-` and an explicit `0` both parse
/// to real values; only the empty string means "clear".
enum AccountOpeningBalanceField {
  static func string(minor: Int?) -> String {
    guard let minor else { return "" }
    return NSDecimalNumber(decimal: Decimal(minor) / 100).stringValue
  }

  static func isValid(_ text: String) -> Bool {
    let sanitized = sanitizeInput(text)
    guard !sanitized.isEmpty else { return true }
    guard Decimal(string: sanitized) != nil else { return false }
    let parts = sanitized.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    return parts.count < 2 || parts[1].count <= 2
  }

  /// Only meaningful once `isValid` has passed, same contract
  /// `EntryAmount.minorUnits` keeps with `EntrySaveGate`.
  static func minorUnits(from text: String) -> Int? {
    let sanitized = sanitizeInput(text)
    guard !sanitized.isEmpty, let decimal = Decimal(string: sanitized) else { return nil }
    let scaled = decimal * 100
    var rounded = Decimal()
    var mutableScaled = scaled
    NSDecimalRound(&rounded, &mutableScaled, 0, .plain)
    return NSDecimalNumber(decimal: rounded).intValue
  }

  /// Keeps digits, a single decimal point, and a single leading `-`.
  private static func sanitizeInput(_ text: String) -> String {
    var seenDecimalPoint = false
    var result = ""
    for (index, character) in text.enumerated() {
      if character == "-" && index == 0 {
        result.append(character)
      } else if character.isNumber {
        result.append(character)
      } else if character == "." && !seenDecimalPoint {
        seenDecimalPoint = true
        result.append(character)
      }
    }
    return result
  }
}

/// Gates the edit sheet's Save button. `displayName`/`lastFour` share exactly
/// `AccountCreateFormGate`'s rules — editing an account cannot be allowed to
/// produce a state creating one couldn't. `institution` has no format rule
/// (free text, same as create). `kindRaw` needs none either: the picker only
/// ever offers `AccountKindOptions.all`. `openingBalanceMinor` is the one
/// genuinely new rule, since it arrives as typed text here, not a picker
/// selection.
enum AccountEditFormGate {
  static func isValid(displayName: String, lastFour: String, openingBalanceText: String) -> Bool {
    AccountCreateFormGate.isValid(displayName: displayName, lastFour: lastFour)
      && AccountOpeningBalanceField.isValid(openingBalanceText)
  }
}

/// The `.confirmationDialog` message for deleting an account (design doc
/// W2-1) — names the transaction count from the summary so the warning is
/// concrete, the way `CategoriesScreen`'s delete dialog names what it
/// cascades rather than reading as a generic warning. Transactions are kept:
/// `AccountStore.delete` only removes the account row and its
/// `AccountBinding`s, and leaves every transaction's `accountID` nil'd —
/// nothing described here is deleted except the account itself.
enum AccountDeleteConfirmation {
  static func message(transactionCount: Int) -> String {
    let subject: String
    switch transactionCount {
    case 0:
      subject = "It has no transactions."
    case 1:
      subject = "Its 1 transaction will be kept, unassigned from any account."
    default:
      subject = "Its \(transactionCount) transactions will be kept, unassigned from any account."
    }
    return "\(subject) This can't be undone."
  }
}
