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

/// The line over the Accounts total (S8 step 4): "Estimated balance", then the day
/// tracking started, as "tracked since 1 Sep". Its own wording: the rename sheet's
/// "Tracked since" line (`TrackedBalanceCaption`) keeps its year and its own prefix.
enum AccountsHeader {
  static func line(trackedSince date: Date?) -> String {
    let label = String(localized: "Estimated balance", bundle: .module)
    guard let date else { return label }
    return label + " · tracked since " + NomiFormatters.dayMonth.string(from: date)
  }
}

/// The text on a physical card (S8 step 2). The title is the institution, else the
/// display name. The second line is the display name when it adds something to the
/// title, else the kind's label.
enum AccountCardText {
  static func title(institution: String, displayName: String) -> String {
    institution.isEmpty ? displayName : institution
  }

  static func subtitle(institution: String, displayName: String, kind: AccountKind) -> String {
    if !institution.isEmpty && displayName != institution {
      return displayName
    }
    return kindLabel(kind)
  }

  static func kindLabel(_ kind: AccountKind) -> String {
    switch kind {
    case .bank: return String(localized: "Bank account", bundle: .module)
    case .card: return String(localized: "Credit card", bundle: .module)
    case .wallet: return String(localized: "Cash", bundle: .module)
    }
  }

  /// "•••• 4471", or nil when there is no last four (a wallet), so the line is left out.
  static func lastFourLine(_ lastFour: String) -> String? {
    lastFour.isEmpty ? nil : "•••• \(lastFour)"
  }
}

/// The VoiceOver label of a card, as the artboard words it: name, account ending,
/// estimated balance in rupees. An owed card says what it owes instead.
enum AccountCardAccessibility {
  static func label(displayName: String, lastFour: String, kind: AccountKind, trackedMinor: Int) -> String {
    var parts = [displayName]
    if !lastFour.isEmpty {
      parts.append(String(localized: "account ending \(lastFour)", bundle: .module))
    }
    let line = AccountBalanceDisplay.line(kind: kind, trackedMinor: trackedMinor)
    if line.caption != nil {
      parts.append(String(localized: "\(spokenRupees(minor: line.minor)) rupees owed", bundle: .module))
    } else {
      parts.append(String(localized: "estimated balance \(spokenRupees(minor: trackedMinor)) rupees", bundle: .module))
    }
    return parts.joined(separator: ", ")
  }

  /// "1,15,271", or "1,234.50" when there are paise, with no symbol and no ".00".
  static func spokenRupees(minor: Int) -> String {
    var digits = NomiFormatters.amountString(minor: minor).replacingOccurrences(of: "₹", with: "")
    if digits.hasSuffix(".00") {
      digits.removeLast(3)
    }
    return (minor < 0 ? "minus " : "") + digits
  }
}

/// The note under the cards (S8 step 4). A catalog plural: one payment, or several.
enum UnassignedNote {
  static func text(count: Int) -> String? {
    guard count > 0 else { return nil }
    return String(localized: "\(count) payment has no account. Assign it so balances stay right.", bundle: .module)
  }
}

/// The accounts the picker offers (S8 step 7): the active ones, plus the selected
/// one even when it is archived, so an existing row's account still shows.
enum AccountPickerFilter {
  static func visible<Row: AccountArchivable>(_ rows: [Row], selection: UUID?) -> [Row] {
    rows.filter { !$0.isArchived || $0.id == selection }
  }
}

/// The create path (S8 step 6): trims the text fields, reads the opening balance as
/// typed, and makes the account in one `create`, so the balance is written with it.
@MainActor
enum AccountCreateAction {
  @discardableResult
  static func perform(
    store: AccountStore,
    displayName: String,
    institution: String,
    lastFour: String,
    kindRaw: String,
    openingBalanceText: String,
    locale: Locale = .current
  ) throws -> Account {
    try store.create(
      displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
      institution: institution.trimmingCharacters(in: .whitespacesAndNewlines),
      lastFour: lastFour,
      kindRaw: kindRaw,
      openingBalanceMinor: AccountOpeningBalanceField.minorUnits(from: openingBalanceText, locale: locale)
    )
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

  /// The stored raw value as a kind. An unrecognised value reads as `.bank`,
  /// the same fallback `Account.kind` uses.
  static func kind(raw: String) -> AccountKind {
    AccountKind(rawValue: raw) ?? .bank
  }
}

/// The choices in the delete confirmation dialog.
enum AccountDeleteChoice: Equatable {
  case archiveInstead
  case delete
}

/// What the screen does with a delete-dialog choice.
enum AccountDeleteOutcome: Equatable {
  /// Present the archive alert, which carries the DEC-06 sentence. Never archive
  /// directly from the dialog: that moves the Tracked balance with no disclosure.
  case presentArchiveAlert
  case deleteAccount
}

/// Routes the delete dialog's choices (AC follow-up F1). "Archive instead" goes
/// to the same archive alert as the row's Archive and the edit sheet's Archive,
/// so every path to an archive shows the same disclosure.
enum AccountDeleteRouting {
  static func outcome(for choice: AccountDeleteChoice) -> AccountDeleteOutcome {
    switch choice {
    case .archiveInstead: return .presentArchiveAlert
    case .delete: return .deleteAccount
    }
  }
}

/// The SF Symbol on an account's row tile. Bank and card share the card
/// glyph, as the approved Accounts artboards draw them.
enum AccountTileSymbol {
  static func name(for kind: AccountKind) -> String {
    switch kind {
    case .bank, .card: return "creditcard"
    case .wallet: return "wallet.pass"
    }
  }
}

/// The second line of an account row: "HDFC Bank ••4471 · 42 transactions". An empty
/// institution or last four is left out rather than printed as a dangling
/// separator (a wallet has no last four).
enum AccountRowText {
  static func subtitle(institution: String, lastFour: String, transactionCount: Int) -> String {
    let maskedLastFour = lastFour.isEmpty ? "" : "••\(lastFour)"
    let identity = [institution, maskedLastFour].filter { !$0.isEmpty }.joined(separator: " ")
    let count = String(localized: "\(transactionCount) transactions", bundle: .module)
    return identity.isEmpty ? count : identity + " · " + count
  }
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
///
/// Validity and parsing are `AmountText` and `AmountRules` (R8, I-8), the same
/// rules every amount field uses. Text is parsed as typed, not sanitised first:
/// a sanitise-then-parse pass would turn `"abc"` into an empty string and read it
/// as "cleared" rather than "invalid". An opening balance may be negative and
/// zero, so this field uses `allowNegative: true` and `isValidOpeningBalance`.
enum AccountOpeningBalanceField {
  static func string(minor: Int?) -> String {
    guard let minor else { return "" }
    return NSDecimalNumber(decimal: Decimal(minor) / 100).stringValue
  }

  /// Empty means "no opening balance" and is valid. Anything else must parse.
  static func isValid(_ text: String, locale: Locale = .current) -> Bool {
    text.isEmpty || AmountText.minorUnits(text, locale: locale, allowNegative: true) != nil
  }

  /// `nil` for empty and for anything invalid. Only meaningful once `isValid` has
  /// passed, same contract `EntryAmount.minorUnits` keeps with `EntrySaveGate`.
  static func minorUnits(from text: String, locale: Locale = .current) -> Int? {
    guard
      !text.isEmpty,
      let minor = AmountText.minorUnits(text, locale: locale, allowNegative: true),
      AmountRules.isValidOpeningBalance(minor)
    else { return nil }
    return minor
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
    default:
      subject = String(localized: "Its \(transactionCount) transactions will be kept, unassigned from any account.", bundle: .module)
    }
    return "\(subject) This can't be undone."
  }
}
