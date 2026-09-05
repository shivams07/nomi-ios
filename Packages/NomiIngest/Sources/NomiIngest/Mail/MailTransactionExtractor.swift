import Foundation
import NomiCore

/// The `(senderDomain, cardFragment)` binding key, normalised. **The only
/// definition of it.**
///
/// Two places must agree byte for byte or a binding is written under one key
/// and looked up under another, and the loop silently never closes: this file
/// when it stamps `TransactionDraft.cardFragment`, and `SwiftDataAccountBindings`
/// when it reads the table. Both call this rather than each doing "trailing
/// four digits" their own way. It lives here because NomiApp can see NomiIngest
/// and not the reverse.
///
/// A pack regex may capture `XX4471`, `4471` or `A/c no. 4471`; the fragment is
/// the last four digits of whatever came back, or `nil` when there are not
/// four - which is the ordinary "the mail did not name an account" case, not
/// an error.
public enum AccountBindingKey {
  public static func domain(_ raw: String) -> String {
    raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  public static func fragment(_ raw: String) -> String? {
    let digits = raw.filter(\.isNumber)
    guard digits.count >= 4 else { return nil }
    return String(digits.suffix(4))
  }
}

/// The MVP's one and only `TransactionExtractor`: the pack-plus-heuristic of
/// §1.4, with the pre-filter in front of it.
///
/// Layer 1 is a regex against a template we already hold — deterministic,
/// unit-testable, instant, correct by construction. Layer 2 is recall with a
/// human gate: every row it produces is `needsReview = true`.
public struct MailTransactionExtractor: TransactionExtractor {
  private let pack: SenderPack
  private let preFilter: MailPreFilter
  private let bindings: any AccountBindingResolving
  private let now: @Sendable () -> Date

  public init(
    pack: SenderPack = .bundled,
    bindings: any AccountBindingResolving = NoAccountBindings(),
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.pack = pack
    self.preFilter = MailPreFilter(pack: pack)
    self.bindings = bindings
    self.now = now
  }

  public func extract(_ message: MailMessage) throws -> TransactionDraft? {
    outcome(for: message).draft
  }

  /// The reporting form. `MailSyncEngine` uses this so it can count
  /// `packMatched` vs `heuristicMatched` (§1.5) without a second extraction.
  public func outcome(for message: MailMessage) -> ExtractionOutcome {
    guard preFilter.isCandidate(message) else { return .notACandidate }

    let text = message.extractableText()

    if let entry = pack.entry(forDomain: message.senderDomain, subject: message.subject),
      let draft = packDraft(message, text: text, entry: entry)
    {
      return ExtractionOutcome(draft: draft, layer: .pack, wasUnparseableCandidate: false)
    }

    if let draft = heuristicDraft(message, text: text) {
      return ExtractionOutcome(draft: draft, layer: .heuristic, wasUnparseableCandidate: false)
    }

    // A real candidate nobody could read. §1.4's safety net: ONE flagged row
    // carrying the raw narration, never a silent miss. A wrong amount you can
    // see beats a transaction that vanished.
    return ExtractionOutcome(
      draft: unparseableDraft(message, text: text),
      layer: .heuristic,
      wasUnparseableCandidate: true
    )
  }

  // MARK: - Layer 1

  private func packDraft(
    _ message: MailMessage, text: String, entry: SenderPackEntry
  ) -> TransactionDraft? {
    // Amount is required. Without it Layer 1 declines the whole message and it
    // falls to Layer 2 — precision over recall, which is why there are two
    // layers rather than one lenient one.
    guard let digits = SenderPackFieldRegexes.capture(entry.fieldRegexes.amount, in: text),
      let amountMinor = MailAmount.paise(fromDigits: digits), amountMinor > 0
    else { return nil }

    guard let direction = packDirection(entry, text: text) else { return nil }

    let date = packDate(entry, text: text) ?? MailDate.firstDate(in: text) ?? message.headerDate
    let fragment = SenderPackFieldRegexes.capture(entry.fieldRegexes.accountFragment, in: text) ?? ""
    let accountID = fragment.isEmpty
      ? nil
      : bindings.accountID(senderDomain: message.senderDomain, cardFragment: fragment)

    return draft(
      message,
      date: date,
      narration: MailNarration.narration(
        in: text, packRegex: entry.fieldRegexes.narration, subject: message.subject),
      amountMinor: amountMinor,
      direction: direction,
      accountID: accountID,
      // §1.2: an unidentified account is flagged, never guessed. A wrong account
      // is silently wrong; an unassigned one is visibly incomplete.
      needsReview: accountID == nil,
      // Layer 1 read the row correctly; the only thing missing is which account
      // it belongs to. That is exactly the flag `setAccount` may clear.
      reason: accountID == nil ? .unidentifiedAccount : nil,
      cardFragment: fragment
    )
  }

  private func packDirection(_ entry: SenderPackEntry, text: String) -> Direction? {
    guard let raw = SenderPackFieldRegexes.capture(entry.fieldRegexes.direction, in: text) else {
      return MailDirection.direction(in: text)
    }
    return MailDirection.direction(in: raw) ?? MailDirection.direction(in: text)
  }

  private func packDate(_ entry: SenderPackEntry, text: String) -> Date? {
    guard let raw = SenderPackFieldRegexes.capture(entry.fieldRegexes.date, in: text) else {
      return nil
    }
    return MailDate.firstDate(in: raw)
  }

  // MARK: - Layer 2

  /// Layer 2 has no pack entry to read a fragment from, so it uses the shape all
  /// five provisional banks happen to share. It is allowed to miss: a missed
  /// fragment leaves `accountID` nil, which §1.2 already handles by flagging.
  private static let genericFragmentPattern =
    #"(?:account|a/c|card)\s*(?:no\.?)?\s*(?:ending\s*)?[Xx*]*(\d{4})"#

  /// The first clause of the body that resolves to a direction — the span the
  /// amount rule measures from.
  ///
  /// Located clause by clause rather than by matching the verb directly: the
  /// verb vocabulary lives in `MailDirection` and is private to it, and a second
  /// copy of that word list here is the copy that goes stale.
  ///
  /// nil when the direction came from the SUBJECT and not the body — "Txn alert"
  /// in the subject, no verb in the body, which real mail does. That case falls
  /// through to `transactionAmount`'s first-amount fallback.
  private static func directionVerbClause(in text: String) -> Range<String.Index>? {
    MailNarration.clauses(in: text).first {
      MailDirection.direction(in: String(text[$0])) != nil
    }
  }

  private func heuristicDraft(_ message: MailMessage, text: String) -> TransactionDraft? {
    // "The amount in the clause the verb is in, the nearest parseable date, the
    // direction from the verb" (§1.4, amended). Largest-wins used to sit here
    // and it took the running balance every time a mail quoted one; the rows are
    // still flagged, but a flagged row carrying a plausible wrong number is worse
    // than a flagged row carrying the right one.
    guard let direction = MailDirection.direction(in: text + " " + message.subject),
      let amountMinor = MailAmount.transactionAmount(
        in: text, verbRange: Self.directionVerbClause(in: text)),
      amountMinor > 0
    else { return nil }

    let date = MailDate.firstDate(in: text) ?? message.headerDate
    let fragment = SenderPackFieldRegexes.capture(
      Self.genericFragmentPattern, in: text) ?? ""
    let accountID = fragment.isEmpty
      ? nil
      : bindings.accountID(senderDomain: message.senderDomain, cardFragment: fragment)

    return draft(
      message,
      date: date,
      narration: MailNarration.narration(in: text, packRegex: nil, subject: message.subject),
      amountMinor: amountMinor,
      direction: direction,
      accountID: accountID,
      needsReview: true,
      // Layer 2 guessed the amount as well as the account, so assigning an
      // account does not make this row reviewed.
      reason: .heuristic,
      cardFragment: fragment
    )
  }

  private func unparseableDraft(_ message: MailMessage, text: String) -> TransactionDraft {
    draft(
      message,
      date: MailDate.firstDate(in: text) ?? message.headerDate,
      narration: MailNarration.narration(in: text, packRegex: nil, subject: message.subject),
      // Zero, not a guess. The review queue shows the raw source and the user
      // types the number; a plausible-and-wrong amount is the one failure mode
      // R6 says to avoid above all others.
      amountMinor: 0,
      direction: MailDirection.direction(in: text + " " + message.subject) ?? .debit,
      accountID: nil,
      needsReview: true,
      reason: .unparseable,
      cardFragment: ""
    )
  }

  // MARK: -

  private func draft(
    _ message: MailMessage,
    date: Date,
    narration: String,
    amountMinor: Int,
    direction: Direction,
    accountID: UUID?,
    needsReview: Bool,
    reason: NeedsReviewReason?,
    cardFragment: String
  ) -> TransactionDraft {
    let unreadableDate = date == Date(timeIntervalSince1970: 0)
    return TransactionDraft(
      date: date,
      descriptionText: narration,
      amountMinor: amountMinor,
      direction: direction,
      currencyCode: "INR",
      accountID: accountID,
      source: .email,
      externalID: message.externalID,
      capturedAt: now(),
      // The epoch is not a date, it is `RFC822Message` reporting that it could
      // not read the `Date:` header. A row dated 1 Jan 1970 that is NOT flagged
      // sorts to the bottom of the ledger and is never seen again, so the
      // fallback has to carry a flag out with it. Checked here rather than at
      // the three call sites because it is a property of the value, not of the
      // layer that produced it.
      needsReview: needsReview || unreadableDate,
      // merchantName / upiKindRaw / counterpartyVPA are deliberately NOT set.
      // U4 derives them from descriptionText (§2.4); an ingester that fills them
      // in trips the pipeline's assert.
      senderDomain: AccountBindingKey.domain(message.senderDomain),
      cardFragment: AccountBindingKey.fragment(cardFragment),
      // The epoch overrides whatever the layer thought, including "the account
      // resolved fine". A 1970 row is the thing worth saying about the row.
      needsReviewReason: unreadableDate ? .unreadableDate : reason
    )
  }
}
