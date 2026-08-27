import Foundation
import NomiCore

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
      needsReview: accountID == nil
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

  private func heuristicDraft(_ message: MailMessage, text: String) -> TransactionDraft? {
    // "The largest currency amount, the nearest parseable date, the direction
    // from the verb" (§1.4). Largest-wins is wrong on a mail that quotes the
    // running balance — which is why every row from here is flagged.
    guard let amountMinor = MailAmount.largestAmount(in: text), amountMinor > 0,
      let direction = MailDirection.direction(in: text + " " + message.subject)
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
      needsReview: true
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
      needsReview: true
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
    needsReview: Bool
  ) -> TransactionDraft {
    TransactionDraft(
      date: date,
      descriptionText: narration,
      amountMinor: amountMinor,
      direction: direction,
      currencyCode: "INR",
      accountID: accountID,
      source: .email,
      externalID: message.externalID,
      capturedAt: now(),
      needsReview: needsReview
      // merchantName / upiKindRaw / counterpartyVPA are deliberately NOT set.
      // U4 derives them from descriptionText (§2.4); an ingester that fills them
      // in trips the pipeline's assert.
    )
  }
}
