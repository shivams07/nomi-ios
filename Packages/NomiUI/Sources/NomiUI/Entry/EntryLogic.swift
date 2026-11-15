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
/// invalid, empty, or out-of-range text resolves to zero, which `EntrySaveGate`
/// then blocks Save on.
///
/// No `Double` anywhere in the conversion (F7/R9). Parsing and the bounds are
/// `AmountText` and `AmountRules` (R8, I-8), so this field and every other amount
/// field agree on what is valid. Grouping separators are read per locale, so
/// "1,234.50" is 123450 in en_IN and "12,50" is 1250 in de_DE.
enum EntryAmount {
  static func minorUnits(from text: String, locale: Locale = .current) -> Int {
    guard
      let minor = AmountText.minorUnits(text, locale: locale, allowNegative: false),
      AmountRules.isValidTransactionAmount(minor)
    else { return 0 }
    return minor
  }

  /// Keeps only digits and the first decimal separator, so the keypad can never
  /// type a second separator or a stray letter into the amount field.
  static func sanitizeInput(_ text: String, locale: Locale = .current) -> String {
    AmountText.filtered(text, locale: locale, allowNegative: false)
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
