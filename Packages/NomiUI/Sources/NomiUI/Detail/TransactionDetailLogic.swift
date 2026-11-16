import Foundation
import NomiCore

/// Pure logic behind `TransactionDetailScreen`, built from plain values rather
/// than `NomiCore.Transaction` (a `@Model` class), so this suite needs no
/// container to exercise it. Not that one cannot be built — it can, under
/// XCTest (see `InMemoryModelContainer`'s measured note in NomiCore) — the
/// values are simply cheaper. Same reasoning as `TransactionRow`'s pure
/// helpers.
public enum TransactionDetailAction: Hashable, Sendable {
  case category, account, edit, source, markReviewed, delete
}

public enum TransactionDetailLogic {
  /// Every row gets the same four base sections and a delete action;
  /// "Mark reviewed" only appears on a row that is actually flagged — there
  /// is nothing to dismiss otherwise.
  public static func availableActions(needsReview: Bool) -> [TransactionDetailAction] {
    var actions: [TransactionDetailAction] = [.category, .account, .edit, .source]
    if needsReview { actions.append(.markReviewed) }
    actions.append(.delete)
    return actions
  }

  /// One line per `SourceRef`, in array order — the Source section lists
  /// every ref a merge accumulated, not just the newest.
  public static func sourceSummary(refs: [SourceRef]) -> [String] {
    refs.map { "\($0.source.rawValue.capitalized) · \($0.externalID)" }
  }

  /// Every reason this screen can see for a row's flags, in a fixed order.
  /// The "Needs review" slot reports the reason mail extraction stored at
  /// ingest when there is one (WR-2, see `reviewReasonText`), else the bare
  /// symptom: the screen cannot see a reason it was not handed. A reason is
  /// only ever shown while `needsReview` is set, so a dismissed row shows none.
  /// `isTransfer` is the row's transfer state (DEC-05 T3): "Transfer" is the
  /// last flag, and it reads `isTransfer` only (Amendment 3, U6).
  public static func flagReasons(
    accountID: UUID?, needsReview: Bool, mergedCount: Int, isTransfer: Bool,
    needsReviewReason: NeedsReviewReason? = nil
  ) -> [String] {
    var reasons: [String] = []
    if accountID == nil { reasons.append("No account assigned") }
    if needsReview { reasons.append(reviewReasonText(needsReviewReason)) }
    if mergedCount > 1 { reasons.append(mergedSourcesText(mergedCount)) }
    if isTransfer { reasons.append("Transfer") }
    return reasons
  }

  /// "Merged from 2 sources", shared by the flag chip and the Source section.
  static func mergedSourcesText(_ count: Int) -> String {
    String(localized: "Merged from \(count) sources", bundle: .module)
  }

  /// The chip text for a flagged row, from the reason ingest stored on it
  /// (WR-2, G2). Each wording says what the user needs to know about the row:
  /// an untrusted sender, or an amount left out of every total. `nil` covers
  /// both a row with no stored reason and a raw value this build does not
  /// know (`Transaction.needsReviewReason` yields nil for it), and keeps the
  /// bare "Needs review". `.unidentifiedAccount` also reads "Needs review": the
  /// "No account assigned" chip already says it. No `default`, so a new
  /// `NeedsReviewReason` case fails to compile here until it has its wording.
  public static func reviewReasonText(_ reason: NeedsReviewReason?) -> String {
    switch reason {
    case .unauthenticatedSender: return "Sender not verified"
    case .foreignCurrency: return "Not in rupees, not counted"
    case .unreadableDate: return "Date couldn't be read"
    case .unparseable: return "Amount couldn't be read"
    case .heuristic: return "Read from an unfamiliar email"
    case .unidentifiedAccount: return "Needs review"
    case nil: return "Needs review"
    }
  }

  /// U24: what `saveEdit()` sends to `TransactionEditing.update`'s `note`
  /// parameter. Blank/whitespace-only input clears the note rather than
  /// storing it — `nil` is what `Transaction.note` uses for "no note", and
  /// the header's "shown when present" check reads exactly that.
  public static func noteToSave(from text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  /// The one primary control on the sheet (SIMP §4 call 1, DT): Apply when a
  /// suggestion panel is on screen, else Mark reviewed when the row is
  /// flagged, else none. `hasSuggestion` means the panel actually shows
  /// (`SuggestionRow.isShown`), not merely that a suggestion was read — a
  /// primary on a hidden button would have no action to press.
  public enum PrimaryAction: Hashable, Sendable {
    case apply, markReviewed, none
  }

  public static func primaryAction(hasSuggestion: Bool, needsReview: Bool) -> PrimaryAction {
    if hasSuggestion { return .apply }
    if needsReview { return .markReviewed }
    return .none
  }

  /// Where "Mark reviewed" is drawn (D7). A flagged row with no suggestion makes
  /// it the sheet's primary, directly under the category row at both detents, so
  /// the medium sheet shows its one primary without a drag. A flagged row with a
  /// suggestion keeps it as the pale secondary in the large details, below Apply.
  /// An unflagged row never shows it.
  public enum MarkReviewedPlacement: Hashable, Sendable {
    case primaryUnderCategory, secondaryInLargeDetails, hidden
  }

  public static func markReviewedPlacement(primary: PrimaryAction, needsReview: Bool) -> MarkReviewedPlacement {
    guard needsReview else { return .hidden }
    switch primary {
    case .markReviewed: return .primaryUnderCategory
    case .apply: return .secondaryInLargeDetails
    case .none: return .hidden
    }
  }

  /// DEC-03 / A-03: a debit is stored and shown negative so its "−" always
  /// prints; a credit is positive so its "+" prints. Works whether the stored
  /// `amountMinor` is the magnitude or already signed, so the sign follows
  /// `direction` and never the stored value.
  public static func signedMinor(amountMinor: Int, direction: Direction) -> Int {
    let magnitude = abs(amountMinor)
    return direction == .debit ? -magnitude : magnitude
  }

  // MARK: - DEC-05 transfer copy (T3)

  /// The sentence a marked transfer carries on Detail. It says what the mark
  /// does to the totals, so a mark never changes a figure the copy does not state.
  public static let transferSentence =
    "Not counted as spending or income. This moves money between your own accounts."

  /// What a mark did when no other row shares the group: this row alone is excluded.
  public static let noMatchSentence =
    "No matching payment found on another account. Only this transaction is excluded."

  /// The other leg of a transfer, as Detail names it. `narration` is that row's
  /// `descriptionText`; `date` is its own date.
  public struct TransferPartner: Equatable, Sendable {
    public let narration: String
    public let date: Date

    public init(narration: String, date: Date) {
      self.narration = narration
      self.date = date
    }
  }

  /// The transfer action's title. It reads `isTransfer` alone, never the row's
  /// source, so the screen offers the same action for every marked row
  /// (Amendment 3, U6).
  public static func transferButtonTitle(isTransfer: Bool) -> String {
    isTransfer ? "Not a transfer" : "Mark as transfer"
  }

  /// What a mark made on this screen did, read back after the write. It names
  /// the partner the editor marked in the same write, or says that only this
  /// row is excluded. A blank partner narration is named "another transaction",
  /// so the sentence never has an empty gap in it.
  public static func markOutcome(partner: TransferPartner?) -> String {
    guard let partner else { return noMatchSentence }
    return "Also marked: \(narrationText(partner.narration)), \(NomiFormatters.dayMonthYear.string(from: partner.date))"
  }

  /// What an unmark made on this screen did. Unmarking clears every row in the
  /// group, so a named partner counts as spending or income again, and so does
  /// this row. Without a partner only this row changes, and the sentence says so.
  public static func unmarkOutcome(partner: TransferPartner?) -> String {
    guard let partner else { return "Now counted as spending or income again." }
    return
      "Also unmarked: \(narrationText(partner.narration)), \(NomiFormatters.dayMonthYear.string(from: partner.date)). Both now count as spending or income."
  }

  private static func narrationText(_ narration: String) -> String {
    let trimmed = narration.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "another transaction" : trimmed
  }
}

/// When the category picker may write. Opening or cancelling the picker reports
/// no pick, and picking the category the row already has is not a change, so
/// neither writes. The screen used to pre-seed the picker and write on that
/// seed, which stamped `.manual` on a row the user had only looked at and so
/// overrode the rule that set it; `TransactionDetailScreen.categorySelection`
/// no longer does. Pulled out as a pure function over plain `UUID`s, the same
/// reason as `RulesReorder`.
enum CategoryPickCommit {
  /// What the picker's selection means for the row. The picker reports a nil
  /// pick only when the user taps None (S3a opts in with `allowsNone`), so nil on
  /// a categorised row clears it. Nil on an uncategorised row is no change.
  enum Decision: Equatable {
    case keep
    case set(UUID)
    case clear
  }

  static func decision(picked: UUID?, current: UUID?) -> Decision {
    switch (picked, current) {
    case (nil, nil): return .keep
    case (nil, _): return .clear
    case (let picked?, let current) where picked == current: return .keep
    case (let picked?, _): return .set(picked)
    }
  }
}

/// M6: the detail screen's "UPI" section prose. Full words, unlike
/// `TransactionRow.upiKindCapsuleText`'s row-width "P2P"/"Merchant" capsule —
/// the two are different presentations of the same raw value, not one
/// reusing the other.
public enum UPIDisplay {
  public static func kindLabel(_ kindRaw: String) -> String? {
    switch kindRaw {
    case "p2p": return "Person"
    case "p2m": return "Merchant"
    default: return nil
    }
  }
}

/// UI refresh (v5) M4: whether the suggestion panel shows, and its two
/// captions. `CategorySuggesting.suggestion(for:)`'s own doc comment already
/// promises `nil` for a `.manual` row or a candidate matching the current
/// category — this mirrors that contract at the UI layer anyway, the same
/// way `NeedsYouCard` mirrors `DashboardWiring.needsYouIsTappable` rather
/// than trusting the read it was handed stayed valid until render.
public enum SuggestionRow {
  public static func isShown(suggestion: CategorySuggestion?, currentCategoryID: UUID?, categorySource: CategorySource) -> Bool {
    guard let suggestion else { return false }
    guard categorySource != .manual else { return false }
    return suggestion.categoryID != currentCategoryID
  }

  /// The panel's third line: "You filed Swiggy as Food & Dining 4 times" or
  /// "Matches your rule for Swiggy". `merchantLabel` is always the row's own
  /// merchant/description label — the screen has no access to a rule's glob
  /// pattern (no `RuleStore` in this unit's init), so the rule caption names
  /// the transaction, not the pattern that matched it.
  public static func reasonText(reason: CategorySuggestion.Reason, merchantLabel: String, categoryName: String) -> String {
    switch reason {
    case .merchantHistory(let matches):
      return String(localized: "You filed \(merchantLabel) as \(categoryName) \(matches) times", bundle: .module)
    case .rule:
      return "Matches your rule for \(merchantLabel)"
    }
  }
}

// MARK: - S3a detail layout

extension TransactionDetailLogic {
  /// The line under the amount: "Today, 13 Nov · 9:42 pm · HDFC ••4471". The day
  /// reads "Today" or "Yesterday" with its day and month, and an older day reads
  /// its day and month only. The time is `h:mm a`. The account is left out when
  /// there is none. Formatted in the calendar's own zone, so the day cannot shift
  /// with the device's zone (see `dateformatter-zone-trap`).
  public static func caption(date: Date, now: Date, calendar: Calendar, accountName: String?) -> String {
    let dayMonth = formatter("d MMM", calendar: calendar)
    let time = formatter("h:mm a", calendar: calendar)
    // The artboard writes "9:42 pm"; en_IN's own day-period symbols are upper case here.
    time.amSymbol = "am"
    time.pmSymbol = "pm"
    let day: String
    if calendar.isDate(date, inSameDayAs: now) {
      day = String(localized: "Today", bundle: .module) + ", " + dayMonth.string(from: date)
    } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
      calendar.isDate(date, inSameDayAs: yesterday)
    {
      day = String(localized: "Yesterday", bundle: .module) + ", " + dayMonth.string(from: date)
    } else {
      day = dayMonth.string(from: date)
    }
    var parts = [day, time.string(from: date)]
    if let accountName, !accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      parts.append(accountName)
    }
    return parts.joined(separator: " · ")
  }

  /// The body of the delete alert: "₹845.00 to Ola on 13 Nov will be removed from
  /// every total." (States board, Destructive).
  public static func deleteConfirmationSentence(amountText: String, merchant: String, date: Date, calendar: Calendar) -> String {
    let day = formatter("d MMM", calendar: calendar).string(from: date)
    return String(localized: "\(amountText) to \(merchant) on \(day) will be removed from every total.", bundle: .module)
  }

  /// The rule row is drawn only where a rule store was handed in, the row is not a
  /// transfer leg (a leg has no category to file), and the row has a pattern.
  public static func showsRuleRow(hasRuleStore: Bool, isTransfer: Bool, pattern: String?) -> Bool {
    hasRuleStore && !isTransfer && pattern != nil
  }

  /// The switch needs a category to file the rule under.
  public static func ruleSwitchEnabled(categoryID: UUID?) -> Bool {
    categoryID != nil
  }

  /// The fields of a `Rule` the "Always use this" switch reads.
  public struct RuleRef: Equatable, Sendable {
    public let id: UUID
    public let pattern: String
    public let categoryID: UUID
    public let isSystem: Bool

    public init(id: UUID, pattern: String, categoryID: UUID, isSystem: Bool) {
      self.id = id
      self.pattern = pattern
      self.categoryID = categoryID
      self.isSystem = isSystem
    }
  }

  /// The user rule the switch reads as on: same pattern and same category. A
  /// system rule is never the switch's rule, since the switch cannot delete it.
  public static func existingRuleID(among rules: [RuleRef], pattern: String, categoryID: UUID) -> UUID? {
    rules.first { !$0.isSystem && $0.pattern == pattern && $0.categoryID == categoryID }?.id
  }

  /// The category chip's words: a transfer leg reads "Transfer", whatever it holds.
  public static func categoryChipText(isTransfer: Bool, categoryName: String?) -> String {
    if isTransfer { return String(localized: "Transfer", bundle: .module) }
    return categoryName ?? String(localized: "Uncategorized", bundle: .module)
  }

  /// The count under the rule switch. The count is what the pattern matches, so
  /// it says "match" (S10's ruling), not "applies". The on state also says the
  /// rule reaches future payments.
  public static func matchCountText(count: Int, isOn: Bool) -> String {
    if isOn {
      return String(localized: "Matches \(count) past transactions and all future ones", bundle: .module)
    }
    return String(localized: "Matches \(count) past transactions", bundle: .module)
  }

  /// The two-second note after a switch-on: how many past rows the new rule
  /// recategorised (`RuleApplyResult.recategorized`).
  public static func appliedText(count: Int) -> String {
    String(localized: "Applied to \(count) transactions", bundle: .module)
  }

  /// What the rule switch writes for a toggle. The switch is read from the rule
  /// store, so a write is decided from the fresh read and never from the
  /// switch's last drawn state. On creates the rule when none exists for the
  /// row's category; off deletes the rule the switch reads (`existingRuleID`).
  public enum RuleSwitchAction: Equatable, Sendable {
    case none
    case create(categoryID: UUID)
    case delete(UUID)
  }

  public static func ruleSwitchAction(turningOn: Bool, existingRuleID: UUID?, categoryID: UUID?) -> RuleSwitchAction {
    if turningOn {
      guard existingRuleID == nil, let categoryID else { return .none }
      return .create(categoryID: categoryID)
    }
    guard let existingRuleID else { return .none }
    return .delete(existingRuleID)
  }

  /// A transfer leg has no category, so its chip does not open the picker.
  public static func categoryChipEnabled(isTransfer: Bool) -> Bool {
    !isTransfer
  }

  /// A transfer leg has no category to suggest, so the panel is never offered.
  public static func suggestionAllowed(isTransfer: Bool) -> Bool {
    !isTransfer
  }

  /// A formatter for the calendar's zone, in en_IN (the app's locale for dates).
  private static func formatter(_ format: String, calendar: Calendar) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_IN")
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = format
    return formatter
  }
}
