import Foundation
import NomiCore

/// The two-tap manual-entry path (U6 done-when): one tap presents `EntryView`,
/// one tap on Save commits it. Amount is the only required input — everything
/// else pulled out here as pure functions so that rule is testable with no
/// container — not because this package's runner cannot build one, which it
/// can under XCTest (see `InMemoryModelContainer`'s measured note in
/// NomiCore).
enum EntryDefaults {
  static let direction: Direction = .debit
}

/// Turns the amount `TextField`'s free-typed text into paise. Never throws —
/// invalid or empty text resolves to zero, which `EntrySaveGate` then blocks
/// Save on.
///
/// No `Double` anywhere in the conversion (F7/R9 — a bare `Double` silently
/// turned "1.999" into ₹2.00). `Decimal(string:)` parses the sanitized text,
/// more than two fraction digits is REJECTED rather than rounded — the same
/// rule `MailAmount.paise` already applies to a parsed mail amount — and the
/// scale to paise goes through `NSDecimalRound`, same as `RowMapper.parseAmountMinor`.
enum EntryAmount {
  static func minorUnits(from text: String) -> Int {
    let sanitized = sanitizeInput(text)
    guard !sanitized.isEmpty, let decimal = Decimal(string: sanitized), decimal > 0 else { return 0 }

    let parts = sanitized.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    if parts.count == 2 && parts[1].count > 2 { return 0 }

    let scaled = decimal * 100
    var rounded = Decimal()
    var mutableScaled = scaled
    NSDecimalRound(&rounded, &mutableScaled, 0, .plain)
    return NSDecimalNumber(decimal: rounded).intValue
  }

  /// Keeps only digits and a single decimal point, so the keypad can never
  /// type a second "." or a stray letter into the amount field.
  static func sanitizeInput(_ text: String) -> String {
    var seenDecimalPoint = false
    var result = ""
    for character in text {
      if character.isNumber {
        result.append(character)
      } else if character == "." && !seenDecimalPoint {
        seenDecimalPoint = true
        result.append(character)
      }
    }
    return result
  }
}

/// Save is enabled the instant the typed amount is positive — no other field
/// on the entry sheet gates it, per the done-when. M3 (v3 amendment): the
/// account chip is prefilled and optional, so this signature must never grow
/// an `accountID` parameter — `EntryAccountTests` pins that down directly.
enum EntrySaveGate {
  static func isEnabled(amountMinor: Int) -> Bool {
    amountMinor > 0
  }
}

/// M3. Kept separate from `NomiCore.Account` so `preselection` is testable
/// with no container — not because this package's runner cannot build one,
/// which it can under XCTest (see `InMemoryModelContainer`'s measured note
/// in NomiCore) — same reason `LedgerRow`/`DatedRow` exist elsewhere in this
/// module. `Account` costs nothing extra to conform.
protocol AccountArchivable {
  var id: UUID { get }
  var isArchived: Bool { get }
}

extension NomiCore.Account: AccountArchivable {}

/// Prefills the entry sheet's account chip — but only when there is exactly
/// one sensible answer. With one active account, "which account" has one
/// value and showing it before Save is a convenience, not a guess. With zero
/// or two-or-more it must NOT guess (§1.2), and the chip stays "Unassigned",
/// one tap from the picker either way.
enum EntryAccountDefault {
  static func preselection<Row: AccountArchivable>(from accounts: [Row]) -> UUID? {
    let active = accounts.filter { !$0.isArchived }
    guard active.count == 1 else { return nil }
    return active[0].id
  }
}
