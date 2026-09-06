import Foundation

/// What the receiving server said about the sender (B9).
public enum MailAuthVerdict: String, Sendable, Equatable {
  case pass, fail, unknown
}

/// Reads the `Authentication-Results` header, and nothing else.
///
/// **This is a report, not a verification.** DKIM signatures are checked by the
/// server that accepted the message; this app never sees the message as that
/// server saw it and could not re-check one if it wanted to. Everything below is
/// therefore only as trustworthy as the topmost header — which is why
/// `RFC822Message` keeps the FIRST `Authentication-Results` it finds. Later ones
/// were written by hops further out and a forger can put anything in those.
///
/// The verdict changes a flag on a row. It never drops a message: R6 says a
/// visible wrong row beats a silent missing one, and the most likely cause of a
/// `fail` in practice is a forwarder or a bank with a broken selector, not an
/// attacker.
public enum MailAuthentication {
  /// - `fail`: `dmarc=fail`, or no dmarc result at all and `dkim=fail` with spf
  ///   not passing. DMARC is the aligned check, so it decides on its own when it
  ///   is present; without it, a failed signature only counts when the envelope
  ///   did not vouch for the sender either.
  /// - `pass`: any of dmarc/dkim/spf reported `pass`.
  /// - `unknown`: no header, an unparseable one, or results that are neither
  ///   (`neutral`, `none`, `temperror`, `policy` — forwarders and generic IMAP
  ///   hosts produce these constantly).
  ///
  /// Order matters: `fail` is tested before `pass`, so `dmarc=fail dkim=pass` —
  /// a valid signature over an unaligned From, i.e. the textbook forgery — is a
  /// fail rather than a pass.
  static func verdict(_ raw: String?) -> MailAuthVerdict {
    guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return .unknown }

    let dmarc = results(for: "dmarc", in: raw)
    let dkim = results(for: "dkim", in: raw)
    let spf = results(for: "spf", in: raw)

    if failed(dmarc) { return .fail }
    if dmarc.isEmpty, failed(dkim), !passed(spf) { return .fail }
    if passed(dmarc) || passed(dkim) || passed(spf) { return .pass }
    return .unknown
  }

  /// A method may appear more than once — one result per DKIM signature is
  /// normal on mail that was signed by both the bank and its ESP. One `pass` is
  /// enough for the method to have passed; `fail` means every result for it
  /// failed and none passed.
  private static func passed(_ results: [String]) -> Bool { results.contains("pass") }

  private static func failed(_ results: [String]) -> Bool {
    !results.contains("pass") && results.contains("fail")
  }

  /// Every `method=result` for one method.
  ///
  /// The leading boundary is `^`, `;`, whitespace or `(` — never a bare word
  /// boundary. `smtp.mailfrom=`, `header.d=` and an `x-dkim=` from some
  /// appliance all sit inside this header, and a `\b` would let the parser read
  /// a result off any of them.
  private static func results(for method: String, in raw: String) -> [String] {
    guard
      let regex = try? NSRegularExpression(
        pattern: "(?:^|[;\\s(])" + method + "\\s*=\\s*([a-z]+)",
        options: [.caseInsensitive])
    else { return [] }

    let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
    return regex.matches(in: raw, range: range).compactMap { match in
      guard let value = Range(match.range(at: 1), in: raw) else { return nil }
      return String(raw[value]).lowercased()
    }
  }
}
