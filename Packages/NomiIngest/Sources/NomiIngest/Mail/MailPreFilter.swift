import Foundation

/// The hard pre-filter (§1.4). Three positive conditions and one negative one.
/// A message is a transaction candidate only if the sender domain is bank-ish,
/// the body carries a currency amount and the body carries a transaction verb —
/// and only if it does NOT carry promotional language.
///
/// This is what satisfies "an email that is not a transaction produces no
/// transaction". A promo from a bank saying *"Get ₹500 cashback"* has the domain
/// and the amount and fails the verb test; a promo from an unknown sender fails
/// at the domain gate and never reaches an extractor at all.
///
/// The fourth condition exists because both of those are the easy cases. The
/// mail that actually reaches the ledger is *"Rs.500 cashback has been credited
/// to your HDFC Bank Card XX4471"* — a bank domain, a real amount, a real credit
/// verb, and not a transaction. No positive test can separate that from an
/// alert; only the vocabulary around it can.
public struct MailPreFilter: Sendable {
  private let pack: SenderPack
  /// Compiled once per filter, not once per message. A sync walks thousands of
  /// messages through `verdict(for:)` and every one of them would otherwise pay
  /// to rebuild the same alternation.
  private let promotionalRegex: CompiledPhrases

  public init(pack: SenderPack = .bundled) {
    self.pack = pack
    self.promotionalRegex = CompiledPhrases(pack.promotionalPhrases ?? [])
  }

  /// `NSRegularExpression` is documented immutable and thread-safe once built,
  /// but whether a given SDK spells that as a `Sendable` conformance is not
  /// something this package should depend on. The guarantee is stated here, on
  /// one field, rather than by putting `@unchecked` on `MailPreFilter` itself —
  /// which would also switch off the compiler's checking of `pack`.
  ///
  /// `MailDirection` gets away with bare `NSRegularExpression` only because its
  /// copies are `static`, and static isolation is not checked under
  /// `StrictConcurrency=targeted`. This one is a stored property, so it is.
  private struct CompiledPhrases: @unchecked Sendable {
    let regex: NSRegularExpression?

    init(_ phrases: [String]) {
      self.regex = MailPhraseMatch.regex(for: phrases)
    }
  }

  public enum Rejection: String, Sendable, Equatable {
    case unknownDomain
    case noCurrencyAmount
    case noTransactionVerb
    /// The fourth condition, and the only NEGATIVE one: everything else here
    /// says why a message failed to qualify, this says a message qualified and
    /// was thrown out anyway.
    case promotional
  }

  public enum Verdict: Sendable, Equatable {
    case candidate
    case rejected(Rejection)
  }

  public func verdict(for message: MailMessage) -> Verdict {
    guard isCandidateDomain(message.senderDomain) else { return .rejected(.unknownDomain) }

    let text = message.extractableText()
    let haystack = text + " " + message.subject

    guard MailAmount.firstAmount(in: haystack) != nil else { return .rejected(.noCurrencyAmount) }
    guard MailDirection.containsTransactionVerb(haystack) else {
      return .rejected(.noTransactionVerb)
    }
    // LAST, and the order is load-bearing in both directions.
    //
    // Running it here is what "rejects the message even when the other three
    // pass" means: the three positive conditions keep their own rejection
    // reasons, so a promo that never had a verb still reports
    // `.noTransactionVerb` and `SyncSummary` does not start counting ordinary
    // marketing as a near-miss. Running it FIRST would relabel five of the six
    // fixtures already on main and destroy that distinction.
    //
    // It also means this condition only ever sees mail that looked exactly like
    // a transaction — which is the population its false-positive rate has to be
    // judged against.
    guard !containsPromotionalLanguage(haystack) else { return .rejected(.promotional) }
    return .candidate
  }

  /// Word-boundary matched, like the verb gate and for the same reason: a
  /// vocabulary matched with `contains` fires inside longer words. `\boffer\b`
  /// must not hit `offered` in "Rs.500 was offered and debited" — and, more to
  /// the point, must not hit inside a merchant name.
  ///
  /// An empty or missing vocabulary rejects nothing. That is the recoverable
  /// direction here: the gate reverts to the three positive conditions, which
  /// is what shipped before this unit, rather than rejecting everything.
  func containsPromotionalLanguage(_ text: String) -> Bool {
    MailPhraseMatch.contains(anyOf: promotionalRegex.regex, in: text)
  }

  /// The vocabulary this filter was actually built with, so a test can assert
  /// over the whole set rather than over the phrases it happens to remember.
  var promotionalPhrases: [String] { pack.promotionalPhrases ?? [] }

  public func isCandidate(_ message: MailMessage) -> Bool {
    verdict(for: message) == .candidate
  }

  /// Three widening rings, and the widest one is load-bearing.
  ///
  /// A gate limited to pack domains would drop every sender the pack does not
  /// know — which is exactly the mail Layer 2 exists for, and exactly the mail
  /// `unmatchedSenders` is supposed to report. The pack cannot be both the
  /// precision list and the admission list.
  func isCandidateDomain(_ domain: String) -> Bool {
    let domain = domain.lowercased()
    guard !domain.isEmpty else { return false }

    if pack.entries.contains(where: { domain == $0.senderDomain || domain.hasSuffix("." + $0.senderDomain) }) {
      return true
    }
    if pack.candidateDomains.contains(where: { domain == $0 || domain.hasSuffix("." + $0) }) {
      return true
    }
    return pack.candidateDomainTokens.contains { domain.contains($0) }
  }
}
