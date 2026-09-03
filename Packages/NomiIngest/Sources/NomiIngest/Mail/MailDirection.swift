import Foundation
import NomiCore

/// Debit or credit, from the verb in the narration.
public enum MailDirection {
  /// Direction resolution runs only on a message that has ALREADY passed the
  /// pre-filter, so it can afford bare `debit` / `credit`. SBI's alert reads
  /// "has a debit by transfer of Rs 3,000.00" and never uses the -ed form.
  ///
  /// The first verb found in the text wins, so an alert that mentions the
  /// transaction before the running balance resolves on the transaction.
  private static let debitVerbs = [
    "debited", "withdrawn", "spent", "charged", "paid", "debit of", "purchase of", "debit",
  ]
  private static let creditVerbs = [
    "credited", "received", "deposited", "refunded", "credit of", "credit",
  ]

  /// The verb set the pre-filter gates on (§1.4), and it is deliberately NOT
  /// `debitVerbs + creditVerbs`.
  ///
  /// Bare `credit` cannot be an admission verb: every promotional mail in India
  /// says "Credit Card", and letting that through would turn the gate off. So
  /// the gate takes the strong forms plus the two multi-word phrasings that are
  /// unambiguous — `has a debit`, `debit by` — which is what lets SBI's mail in
  /// without letting a card offer in with it.
  public static let candidateVerbs = [
    "debited", "credited", "spent", "withdrawn", "charged", "received", "paid",
    "transaction of", "transaction alert",
    "has a debit", "has a credit", "debit by", "credit by",
  ]

  /// Matched on WORD BOUNDARIES, never as a substring.
  ///
  /// `lower.contains("paid")` admitted `prepaid`, `postpaid` and `unpaid`;
  /// `lower.contains("charged")` admitted `recharged`. Every one of those
  /// carries a bank domain and a currency amount, so the verb was the only gate
  /// still standing between a telecom promo and a transaction row.
  public static func containsTransactionVerb(_ text: String) -> Bool {
    MailPhraseMatch.contains(anyOf: candidateVerbRegex, in: text)
  }

  /// `nil` when no verb is present at all — the caller decides whether that is a
  /// rejection (pre-filter) or a `needsReview` row (Layer 2).
  ///
  /// Word-boundary matched for the same reason `containsTransactionVerb` is,
  /// and it is the same defect: `range(of: "paid")` hits inside `prepaid`, and
  /// because this resolves on the EARLIEST verb, "your prepaid card has been
  /// credited" resolved to `.debit`. Direction runs after admission, so nothing
  /// upstream would have caught it.
  public static func direction(in text: String) -> Direction? {
    let lower = text.lowercased()
    let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)

    let debit = debitVerbRegex?.firstMatch(in: lower, range: range)?.range.location
    let credit = creditVerbRegex?.firstMatch(in: lower, range: range)?.range.location

    switch (debit, credit) {
    // A tie resolves to debit, which is the order the two lists were scanned in
    // before this was a regex.
    case let (debitAt?, creditAt?): return debitAt <= creditAt ? .debit : .credit
    case (_?, nil): return .debit
    case (nil, _?): return .credit
    case (nil, nil): return nil
    }
  }

  private static let candidateVerbRegex = MailPhraseMatch.regex(for: candidateVerbs)
  private static let debitVerbRegex = MailPhraseMatch.regex(for: debitVerbs)
  private static let creditVerbRegex = MailPhraseMatch.regex(for: creditVerbs)
}

/// Whole-word matching for a list of phrases held as data.
///
/// Shared by the verb gate and the promotional gate because they are the same
/// mistake waiting to happen twice: a vocabulary list matched with `contains`
/// fires inside longer words, and the failure is silent in both directions —
/// mail admitted that should not be, mail rejected that should not be.
enum MailPhraseMatch {
  /// `nil` only if every phrase is empty or the alternation fails to compile —
  /// neither is reachable from the constants in this module, and both are
  /// treated as "matches nothing" rather than trapping. For the verb gate that
  /// means no mail is admitted; for the promotional gate it means none is
  /// rejected. Both fail towards doing nothing, which is the recoverable
  /// direction: an empty ledger is visible, a wrong row is not.
  static func regex(for phrases: [String]) -> NSRegularExpression? {
    let alternation =
      phrases
      .filter { !$0.isEmpty }
      .map { NSRegularExpression.escapedPattern(for: $0) }
      .joined(separator: "|")
    guard !alternation.isEmpty else { return nil }
    return try? NSRegularExpression(
      pattern: "\\b(?:" + alternation + ")\\b", options: [.caseInsensitive])
  }

  static func contains(anyOf regex: NSRegularExpression?, in text: String) -> Bool {
    guard let regex else { return false }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return regex.firstMatch(in: text, range: range) != nil
  }
}
