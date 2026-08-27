import Foundation

/// The hard pre-filter (§1.4). A message is a transaction candidate only if all
/// three hold: the sender domain is bank-ish, the body carries a currency
/// amount, and the body carries a transaction verb.
///
/// This is what satisfies "an email that is not a transaction produces no
/// transaction". A promo from a bank saying *"Get ₹500 cashback"* has the domain
/// and the amount and fails the verb test; a promo from an unknown sender fails
/// at the domain gate and never reaches an extractor at all.
public struct MailPreFilter: Sendable {
  private let pack: SenderPack

  public init(pack: SenderPack = .bundled) {
    self.pack = pack
  }

  public enum Rejection: String, Sendable, Equatable {
    case unknownDomain
    case noCurrencyAmount
    case noTransactionVerb
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
    return .candidate
  }

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
