import NomiCore

/// The two-tap manual-entry path (U6 done-when): one tap presents `EntryView`,
/// one tap on Save commits it. Amount is the only required input — everything
/// else pulled out here as pure functions so that rule is directly testable
/// without constructing an `@Model` instance (see `InMemoryModelContainer`'s
/// note in NomiCore: this package's `swift test` runner cannot do that
/// headlessly).
enum EntryDefaults {
  static let direction: Direction = .debit
}

/// Turns the amount `TextField`'s free-typed text into paise. Never throws —
/// invalid or empty text resolves to zero, which `EntrySaveGate` then blocks
/// Save on.
enum EntryAmount {
  static func minorUnits(from text: String) -> Int {
    let sanitized = sanitizeInput(text)
    guard let value = Double(sanitized), value.isFinite, value > 0 else { return 0 }
    return Int((value * 100).rounded())
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
/// on the entry sheet gates it, per the done-when.
enum EntrySaveGate {
  static func isEnabled(amountMinor: Int) -> Bool {
    amountMinor > 0
  }
}
