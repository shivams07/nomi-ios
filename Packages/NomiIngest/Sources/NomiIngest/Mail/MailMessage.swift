import Foundation

/// One fetched email, already decoded from the wire.
///
/// This is what `FETCH BODY.PEEK[]` yields after `RFC822Message` has run over
/// it, and it is also exactly what a `.eml` file on disk parses to — which is
/// deliberate. The fixtures under `Tests/NomiIngestTests/Fixtures/Mail/` are
/// real `.eml` files, so a saved message from Shivam's mailbox drops into the
/// same test suite with no code change (§2.5.2).
public struct MailMessage: Sendable, Equatable {
  /// IMAP UID, scoped by mailbox and UIDVALIDITY. See `externalID`.
  public let uid: UInt32
  public let uidValidity: UInt32
  public let mailboxName: String

  /// Full `From:` value as sent, e.g. `"HDFC Bank Alerts <alerts@hdfcbank.net>"`.
  /// **Never** put this in a `SyncSummary` — see `UnmatchedSenderTally`.
  public let fromRaw: String
  public let subject: String
  /// The `Date:` header. The fallback when no date can be read from the body.
  public let headerDate: Date

  /// `text/html` part, if the message had one.
  public let htmlBody: String?
  /// `text/plain` part, if the message had one.
  public let textBody: String?

  public init(
    uid: UInt32,
    uidValidity: UInt32,
    mailboxName: String = "INBOX",
    fromRaw: String,
    subject: String,
    headerDate: Date,
    htmlBody: String?,
    textBody: String?
  ) {
    self.uid = uid
    self.uidValidity = uidValidity
    self.mailboxName = mailboxName
    self.fromRaw = fromRaw
    self.subject = subject
    self.headerDate = headerDate
    self.htmlBody = htmlBody
    self.textBody = textBody
  }

  /// The bare address inside `fromRaw`, lowercased. `""` when there isn't one.
  public var senderAddress: String {
    guard let open = fromRaw.lastIndex(of: "<"), let close = fromRaw.lastIndex(of: ">"),
      open < close
    else {
      return fromRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    return String(fromRaw[fromRaw.index(after: open)..<close])
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
  }

  /// Everything after the `@`, lowercased. This — and only this — is what may
  /// leave the device in a `SyncSummary` (§2.5.1).
  public var senderDomain: String {
    let address = senderAddress
    guard let at = address.lastIndex(of: "@") else { return "" }
    return String(address[address.index(after: at)...])
  }

  /// `mailbox/uidvalidity/uid`. UIDs are unique only within a mailbox at a given
  /// UIDVALIDITY, so all three are needed or a server-side mailbox rebuild would
  /// silently collide two different messages onto one `SourceRef`.
  ///
  /// A UIDVALIDITY change does re-ingest the mailbox under fresh externalIDs.
  /// That is safe but not free: the pipeline's tier-1 exact `dedupeKey` match
  /// catches every one of them and no duplicate row is created.
  public var externalID: String {
    "\(mailboxName)/\(uidValidity)/\(uid)"
  }

  /// The body the extractors read: HTML converted to text when there is HTML,
  /// the plain part otherwise. Never the raw HTML source — regexing that is R6,
  /// the wrong-amount generator.
  public func extractableText() -> String {
    if let html = htmlBody, !html.isEmpty {
      return MailHTML.plainText(fromHTML: html)
    }
    return MailHTML.normalizeWhitespace(textBody ?? "")
  }
}
