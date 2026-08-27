import Foundation
import NomiCore

/// The exact bytes this client puts on the wire.
///
/// Commands are built as text rather than through `NIOIMAP`'s encoder, and that
/// is not a shortcut: `CommandEncoder` and `CommandEncodeBuffer.writeCommandStream`
/// are `internal` / `@_spi(NIOIMAPInternal)` in swift-nio-imap 0.4.0, so no
/// caller outside that module can reach them. Encoding an IMAP command is
/// unambiguous text and this is testable byte-for-byte, which is what
/// `IMAPCommandTests` does.
///
/// Response *parsing* is the opposite case — nested literals and FETCH streaming
/// are where a hand-rolled parser earns its bugs — and that half is deliberately
/// not here. See `IMAPResponseReading`.
public struct IMAPCommand: Equatable, Sendable {
  public let tag: String
  /// The command text, without the tag and without CRLF.
  public let body: String

  public init(tag: String, body: String) {
    self.tag = tag
    self.body = body
  }

  /// `"a001 EXAMINE INBOX\r\n"` — tag, space, body, CRLF. IMAP lines end CRLF,
  /// never LF.
  public var wireText: String { "\(tag) \(body)\r\n" }
  public var wireBytes: [UInt8] { Array(wireText.utf8) }

  // MARK: - The five commands this client issues

  public static func login(tag: String, address: String, password: String) -> IMAPCommand {
    IMAPCommand(tag: tag, body: "LOGIN \(quoted(address)) \(quoted(password))")
  }

  /// `EXAMINE`, never `SELECT`.
  ///
  /// Both open a mailbox; `EXAMINE` opens it read-only. The app has no business
  /// writing to a mailbox it does not own, and read-only-by-construction is a
  /// stronger guarantee than remembering not to issue a write command.
  public static func examine(tag: String, mailbox: String) -> IMAPCommand {
    IMAPCommand(tag: tag, body: "EXAMINE \(quoted(mailbox))")
  }

  /// `UID SEARCH SINCE <dd-MMM-yyyy>` — the six-month backfill.
  ///
  /// IMAP's date format is its own (`12-Aug-2026`) and is case- and
  /// locale-sensitive, so the formatter is pinned to `en_US_POSIX` and UTC. A
  /// device in a Hindi locale would otherwise emit a month name no server
  /// understands.
  public static func uidSearchSince(tag: String, date: Date) -> IMAPCommand {
    IMAPCommand(tag: tag, body: "UID SEARCH SINCE \(imapDate(date))")
  }

  /// `UID SEARCH UID <n+1>:*` — incremental sync above the cursor.
  ///
  /// `n + 1` rather than `n`, or every sync re-fetches the last message it
  /// already had. Saturates rather than wrapping at `UInt32.max`.
  public static func uidSearchAfter(tag: String, uid: UInt32) -> IMAPCommand {
    let next = uid == UInt32.max ? UInt32.max : uid + 1
    return IMAPCommand(tag: tag, body: "UID SEARCH UID \(next):*")
  }

  /// **`BODY.PEEK[]`, never `BODY[]`** (R4).
  ///
  /// `BODY[]` sets `\Seen` on the user's real mail as a side effect of merely
  /// scanning it — a visible, annoying, hard-to-undo change to a mailbox this
  /// app does not own. `IMAPCommandTests` asserts the literal absence of a bare
  /// `BODY[` in every command this type can produce, because this is the one
  /// mistake here that a user would notice and could not undo.
  public static func uidFetchBodyPeek(tag: String, uids: [UInt32]) -> IMAPCommand {
    IMAPCommand(tag: tag, body: "UID FETCH \(uidSet(uids)) (UID BODY.PEEK[])")
  }

  /// IDLE while foregrounded (§1.3). Terminated by the literal line `DONE`,
  /// which carries no tag — that is the protocol, not an omission.
  public static func idle(tag: String) -> IMAPCommand {
    IMAPCommand(tag: tag, body: "IDLE")
  }

  public static let idleDoneWireText = "DONE\r\n"

  public static func logout(tag: String) -> IMAPCommand {
    IMAPCommand(tag: tag, body: "LOGOUT")
  }

  // MARK: -

  /// Collapses runs into ranges: `[4,5,6,9]` -> `"4:6,9"`.
  ///
  /// Not cosmetic. A backfill can select several thousand UIDs and IMAP servers
  /// enforce a line-length limit; a comma-separated list of every UID overflows
  /// it and the fetch fails outright.
  static func uidSet(_ uids: [UInt32]) -> String {
    let sorted = Array(Set(uids)).sorted()
    guard !sorted.isEmpty else { return "" }

    var parts: [String] = []
    var start = sorted[0]
    var previous = sorted[0]

    for uid in sorted.dropFirst() {
      if uid == previous + 1 {
        previous = uid
        continue
      }
      parts.append(start == previous ? "\(start)" : "\(start):\(previous)")
      start = uid
      previous = uid
    }
    parts.append(start == previous ? "\(start)" : "\(start):\(previous)")
    return parts.joined(separator: ",")
  }

  /// IMAP quoted-string: backslash and double-quote are the only escapes.
  ///
  /// This is what stops a password containing `"` from ending the string early
  /// and turning the rest of it into command syntax.
  static func quoted(_ raw: String) -> String {
    let escaped = raw
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
  }

  static func imapDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "dd-MMM-yyyy"
    return formatter.string(from: date)
  }
}

/// Sequential command tags: `a001`, `a002`, …
///
/// A tag must be unique for the lifetime of a connection — it is how a response
/// is matched to the command that caused it. Reusing one makes two commands'
/// completions indistinguishable.
public struct IMAPTagGenerator: Sendable {
  private var counter = 0
  private let prefix: String

  public init(prefix: String = "a") {
    self.prefix = prefix
  }

  public mutating func next() -> String {
    counter += 1
    return String(format: "%@%03d", prefix, counter)
  }
}
