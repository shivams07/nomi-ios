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

  public static func containsTransactionVerb(_ text: String) -> Bool {
    let lower = text.lowercased()
    return candidateVerbs.contains { lower.contains($0) }
  }

  /// `nil` when no verb is present at all — the caller decides whether that is a
  /// rejection (pre-filter) or a `needsReview` row (Layer 2).
  public static func direction(in text: String) -> Direction? {
    let lower = text.lowercased()

    var earliest: (index: String.Index, direction: Direction)?
    for (verbs, direction) in [(debitVerbs, Direction.debit), (creditVerbs, Direction.credit)] {
      for verb in verbs {
        guard let found = lower.range(of: verb) else { continue }
        if earliest == nil || found.lowerBound < earliest!.index {
          earliest = (found.lowerBound, direction)
        }
      }
    }
    return earliest?.direction
  }
}
