import Foundation

public struct UPIParseResult: Sendable, Equatable {
  public let merchantName: String
  public let upiKindRaw: String   // "p2p" | "p2m"
  public let counterpartyVPA: String?

  public init(merchantName: String, upiKindRaw: String, counterpartyVPA: String?) {
    self.merchantName = merchantName
    self.upiKindRaw = upiKindRaw
    self.counterpartyVPA = counterpartyVPA
  }
}

/// Pure, no I/O. Parses raw bank narration for UPI transactions into display-only
/// fields. Never touches `dedupeKey` or `normalizedDescription` — see design §2.4.
/// Unmatched input returns nil; the row falls back to its raw narration.
public enum UPINarration {

  // UPI/P2M/<ref>/<name>/<bank>/<note>  or  UPI/P2P/...
  private static let slashFormRegex = try! NSRegularExpression(
    pattern: #"^UPI/(P2M|P2P)/([^/]*)/([^/]*)/([^/]*)(?:/(.*))?$"#,
    options: [.caseInsensitive]
  )

  // UPI-<NAME>-<vpa>-...  (SBI hyphen variant)
  private static let hyphenFormRegex = try! NSRegularExpression(
    pattern: #"^UPI-([^-]+)-([A-Za-z0-9._]+@[A-Za-z0-9._]+)-"#,
    options: [.caseInsensitive]
  )

  // bare <vpa>@<handle> form embedded anywhere in the narration
  private static let vpaRegex = try! NSRegularExpression(
    pattern: #"([A-Za-z0-9.\-_]{2,})@([A-Za-z]{2,})"#,
    options: []
  )

  public static func parse(_ narration: String) -> UPIParseResult? {
    let trimmed = narration.trimmingCharacters(in: .whitespacesAndNewlines)
    let full = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)

    if let match = slashFormRegex.firstMatch(in: trimmed, range: full) {
      let kind = substring(trimmed, match, 1).uppercased() == "P2M" ? "p2m" : "p2p"
      let name = substring(trimmed, match, 3)
      let vpaCandidate = substring(trimmed, match, 2)
      let vpa = vpaCandidate.contains("@") ? vpaCandidate : nil
      guard !name.isEmpty else { return nil }
      return UPIParseResult(merchantName: name, upiKindRaw: kind, counterpartyVPA: vpa)
    }

    if let match = hyphenFormRegex.firstMatch(in: trimmed, range: full) {
      let name = substring(trimmed, match, 1)
      let vpa = substring(trimmed, match, 2)
      guard !name.isEmpty else { return nil }
      let kind = vpa.lowercased().contains("ok") || vpa.contains(".") ? "p2m" : "p2p"
      return UPIParseResult(merchantName: name, upiKindRaw: kind, counterpartyVPA: vpa)
    }

    if let match = vpaRegex.firstMatch(in: trimmed, range: full) {
      let vpa = substring(trimmed, match, 0)
      let name = substring(trimmed, match, 1)
      guard !name.isEmpty else { return nil }
      return UPIParseResult(merchantName: name, upiKindRaw: "p2p", counterpartyVPA: vpa)
    }

    return nil
  }

  private static func substring(_ source: String, _ match: NSTextCheckingResult, _ group: Int) -> String {
    guard let range = Range(match.range(at: group), in: source) else { return "" }
    return String(source[range])
  }
}
