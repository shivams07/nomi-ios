import Foundation
import NomiCore

/// Layer 1's data. A bundled JSON pack of per-sender extraction patterns, so
/// adding a bank is a data edit and not a code change (§1.4).
public struct SenderPack: Codable, Sendable, Equatable {
  /// Carried in the JSON and never read by code. It exists so anyone opening the
  /// file sees the provisional warning before they read the bank list (§2.5.1).
  public let readme: String
  public let version: Int
  /// Exact domains that are transaction-mail candidates but have no pack entry.
  /// This is what lets Layer 2 ever run: the pre-filter's domain gate has to be
  /// wider than the pack or a sender with no entry would be dropped before any
  /// extractor saw it.
  public let candidateDomains: [String]
  /// Substrings that make an unknown domain a candidate — `bank`, `card`, `upi`.
  /// Wider still, and the reason `unmatchedSenders` has anything to report.
  public let candidateDomainTokens: [String]
  public let entries: [SenderPackEntry]

  enum CodingKeys: String, CodingKey {
    case readme = "_readme"
    case version, candidateDomains, candidateDomainTokens, entries
  }

  public func entry(forDomain domain: String, subject: String) -> SenderPackEntry? {
    entries.first { $0.matches(domain: domain, subject: subject) }
  }

  /// The bundled pack, read from `Resources/senders.json`. Parsed once.
  ///
  /// It is a real resource rather than a Swift literal because §2.5.1 and §2.5.2
  /// both rest on the pack being *data*: correcting it is one JSON entry per
  /// bank, no code change and no unit. The pack is *expected* to be partly wrong,
  /// so that property is the one thing not to trade away. `Package.swift` carries
  /// the `resources:` line §2.10 authorised for exactly this.
  ///
  /// A malformed or missing file returns an empty pack rather than trapping:
  /// Layer 2 still extracts, every row lands in the review queue, and the user
  /// sees degraded results instead of a crash on launch.
  public static let bundled: SenderPack = load() ?? .empty

  static let empty = SenderPack(
    readme: "", version: 0, candidateDomains: [], candidateDomainTokens: [], entries: [])

  /// `Bundle.module` is synthesised per target, so the test target cannot name
  /// NomiIngest's. This is how a test reaches it.
  static var resourceBundle: Bundle { .module }

  static func load(from bundle: Bundle = .module) -> SenderPack? {
    guard let url = bundle.url(forResource: "senders", withExtension: "json"),
      let data = try? Data(contentsOf: url)
    else { return nil }
    return try? JSONDecoder().decode(SenderPack.self, from: data)
  }

  public init(
    readme: String,
    version: Int,
    candidateDomains: [String],
    candidateDomainTokens: [String],
    entries: [SenderPackEntry]
  ) {
    self.readme = readme
    self.version = version
    self.candidateDomains = candidateDomains
    self.candidateDomainTokens = candidateDomainTokens
    self.entries = entries
  }
}

public struct SenderPackEntry: Codable, Sendable, Equatable {
  /// Matched as a suffix, so `alerts.hdfcbank.net` hits the `hdfcbank.net`
  /// entry. Banks add and drop alert subdomains without notice.
  public let senderDomain: String
  public let bankLabel: String
  /// `nil` means "any subject from this domain". Case-insensitive.
  public let subjectPattern: String?
  public let fieldRegexes: SenderPackFieldRegexes
  /// Seeds `Account.institution` when the app later creates an account for this
  /// sender. Never used to guess an `accountID` — §1.2 forbids guessing.
  public let accountHint: String?

  public init(
    senderDomain: String,
    bankLabel: String,
    subjectPattern: String?,
    fieldRegexes: SenderPackFieldRegexes,
    accountHint: String?
  ) {
    self.senderDomain = senderDomain
    self.bankLabel = bankLabel
    self.subjectPattern = subjectPattern
    self.fieldRegexes = fieldRegexes
    self.accountHint = accountHint
  }

  public func matches(domain: String, subject: String) -> Bool {
    let domain = domain.lowercased()
    guard domain == senderDomain || domain.hasSuffix("." + senderDomain) else { return false }
    guard let pattern = subjectPattern else { return true }
    return subject.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
  }
}

/// Capture group 1 of each regex is the value. A regex that is absent, or that
/// does not match, makes Layer 1 decline that field.
public struct SenderPackFieldRegexes: Codable, Sendable, Equatable {
  /// Required. If this does not match, Layer 1 declines the message entirely and
  /// it falls through to Layer 2 — precision over recall, which is the whole
  /// point of having two layers.
  public let amount: String
  public let date: String?
  public let direction: String?
  /// The last four of the account or card, e.g. `XX1234` -> `1234`.
  public let accountFragment: String?
  /// The raw narration to carry into `descriptionText`. Optional: when it is
  /// absent or does not match, `MailNarration` falls back to a UPI reference and
  /// then to the clause around the amount. Never post-processed here - §2.4
  /// gives narration parsing to U4.
  public let narration: String?

  public init(
    amount: String,
    date: String?,
    direction: String?,
    accountFragment: String?,
    narration: String? = nil
  ) {
    self.amount = amount
    self.date = date
    self.direction = direction
    self.accountFragment = accountFragment
    self.narration = narration
  }
}

extension SenderPackFieldRegexes {
  /// First capture group of `pattern` in `text`, or nil.
  static func capture(_ pattern: String?, in text: String) -> String? {
    guard let pattern,
      let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    else { return nil }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
      let captured = Range(match.range(at: 1), in: text)
    else { return nil }
    return String(text[captured])
  }
}
