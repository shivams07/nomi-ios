import Foundation
import NomiCore
import XCTest

@testable import NomiIngest

/// The command half of the transport, verified byte-for-byte against a recorded
/// session. No network, no server, no toolchain beyond the test runner.
final class IMAPCommandTests: XCTestCase {

  // MARK: - R4: BODY.PEEK, never BODY

  /// The single most consequential line in this unit. `BODY[]` sets `\Seen` on
  /// the user's real mail as a side effect of scanning it — a change to a
  /// mailbox this app does not own, which the user WILL notice and cannot
  /// undo. Asserted positively and negatively.
  func testUIDFetchUsesBodyPeekAndNeverBareBody() {
    let command = IMAPCommand.uidFetchBodyPeek(tag: "a004", uids: [4389, 4390, 4391])

    XCTAssertEqual(command.wireText, "a004 UID FETCH 4389:4391 (UID BODY.PEEK[])\r\n")
    XCTAssertTrue(command.body.contains("BODY.PEEK["))
    XCTAssertFalse(command.body.contains(" BODY["))
  }

  /// Every command this type can produce, swept for a bare `BODY[`. A future
  /// command added without reading R4 fails here rather than in someone's inbox.
  func testNoCommandThisClientCanIssueContainsABareBody() {
    let commands: [IMAPCommand] = [
      .login(tag: "a001", address: "a@b.com", password: "pw"),
      .examine(tag: "a002", mailbox: "INBOX"),
      .uidSearchSince(tag: "a003", date: Date(timeIntervalSince1970: 1_787_000_000)),
      .uidSearchBetween(
        tag: "a003b",
        since: Date(timeIntervalSince1970: 1_786_000_000),
        before: Date(timeIntervalSince1970: 1_787_000_000)),
      .uidSearchAfter(tag: "a004", uid: 4388),
      .uidFetchBodyPeek(tag: "a005", uids: [1]),
      .idle(tag: "a006"),
      .logout(tag: "a007"),
    ]

    for command in commands {
      let withoutPeek = command.body.replacingOccurrences(of: "BODY.PEEK[", with: "")
      XCTAssertFalse(withoutPeek.contains("BODY["), command.body)
    }
  }

  // MARK: - EXAMINE, not SELECT

  func testMailboxIsOpenedReadOnly() {
    let command = IMAPCommand.examine(tag: "a002", mailbox: "INBOX")
    XCTAssertEqual(command.wireText, "a002 EXAMINE \"INBOX\"\r\n")
    XCTAssertFalse(command.body.hasPrefix("SELECT"))
  }

  // MARK: - The recorded session

  /// Reproduces every client line of a recorded dialogue from the command
  /// builders. If a builder's wire format drifts, this fails with the exact
  /// line.
  func testEveryClientLineOfTheRecordedSessionIsReproducedExactly() throws {
    let transcript = try IMAPTranscript.load("gmail_sync_session.txt")

    let produced = [
      IMAPCommand.login(
        tag: "a001", address: "shivam@example.com", password: "abcd efgh ijkl mnop"),
      IMAPCommand.examine(tag: "a002", mailbox: "INBOX"),
      IMAPCommand.uidSearchAfter(tag: "a003", uid: 4387),
      IMAPCommand.uidFetchBodyPeek(tag: "a004", uids: [4389, 4390, 4391]),
      IMAPCommand.logout(tag: "a005"),
    ].map(\.body)

    let expectedBodies = transcript.clientLines.map { line -> String in
      // Drop the tag; tag generation is covered by testTagsAreSequentialAndUnique.
      String(line.drop(while: { $0 != " " }).dropFirst())
    }

    XCTAssertEqual(transcript.clientLines.count, 5)
    XCTAssertEqual(produced, expectedBodies)
  }

  func testTheRecordedSessionOpensReadOnlyAndPeeks() throws {
    let transcript = try IMAPTranscript.load("gmail_sync_session.txt")
    let joined = transcript.clientLines.joined(separator: "\n")

    XCTAssertTrue(joined.contains("EXAMINE"))
    XCTAssertFalse(joined.contains("SELECT"))
    XCTAssertTrue(joined.contains("BODY.PEEK[]"))
    XCTAssertFalse(joined.replacingOccurrences(of: "BODY.PEEK[", with: "").contains("BODY["))
  }

  // MARK: - UID sets

  /// A backfill can select several thousand UIDs. A comma-separated list of
  /// every one of them overflows the server's line-length limit and the fetch
  /// fails outright, so runs collapse to ranges.
  func testUIDSetsCollapseRunsIntoRanges() {
    XCTAssertEqual(IMAPCommand.uidSet([4, 5, 6, 9]), "4:6,9")
    XCTAssertEqual(IMAPCommand.uidSet([1]), "1")
    XCTAssertEqual(IMAPCommand.uidSet([3, 1, 2]), "1:3")
    XCTAssertEqual(IMAPCommand.uidSet([1, 3, 5]), "1,3,5")
    XCTAssertEqual(IMAPCommand.uidSet([7, 7, 8]), "7:8")
    XCTAssertEqual(IMAPCommand.uidSet([]), "")
  }

  func testALongContiguousRangeIsOneShortToken() {
    let uids = (1...5000).map(UInt32.init)
    XCTAssertEqual(IMAPCommand.uidSet(uids), "1:5000")
  }

  // MARK: - Incremental search

  /// `n + 1`, not `n`, or every sync re-fetches the message it already had.
  func testIncrementalSearchStartsAboveTheCursor() {
    XCTAssertEqual(
      IMAPCommand.uidSearchAfter(tag: "a1", uid: 4388).body, "UID SEARCH UID 4389:*")
  }

  func testIncrementalSearchSaturatesRatherThanWrapping() {
    XCTAssertEqual(
      IMAPCommand.uidSearchAfter(tag: "a1", uid: .max).body,
      "UID SEARCH UID \(UInt32.max):*")
  }

  // MARK: - Dates and quoting

  /// IMAP's date format is its own, and it is locale-sensitive. A device set to
  /// a Hindi locale would otherwise emit a month name no server understands.
  func testSearchDatesUseIMAPFormatInAFixedLocale() {
    let date = Date(timeIntervalSince1970: 1_786_000_000)  // 06 Aug 2026, 07:06 UTC
    XCTAssertEqual(IMAPCommand.imapDate(date), "06-Aug-2026")
    XCTAssertEqual(
      IMAPCommand.uidSearchSince(tag: "a1", date: date).body, "UID SEARCH SINCE 06-Aug-2026")
  }

  /// One window of the backfill walk (§2.17). `SINCE` inclusive, `BEFORE`
  /// exclusive, both date-granular — the server discards the time of day, so the
  /// two dates are the whole meaning of the request.
  func testAWindowedSearchCarriesBothBoundsInOrder() {
    let command = IMAPCommand.uidSearchBetween(
      tag: "a003",
      since: Date(timeIntervalSince1970: 1_786_000_000),  // 06 Aug 2026
      before: Date(timeIntervalSince1970: 1_788_600_000)  // 05 Sep 2026
    )
    XCTAssertEqual(
      command.wireText, "a003 UID SEARCH SINCE 06-Aug-2026 BEFORE 05-Sep-2026\r\n")
  }

  /// The transport passes the engine's dates through untouched. The overlap
  /// between adjacent windows is deliberate — dedupe absorbs a duplicate, and
  /// nothing recovers a day dropped by a boundary someone tightened here.
  func testTheWindowBoundsAreNotAdjustedByTheTransport() {
    let since = Date(timeIntervalSince1970: 1_786_000_000)
    let command = IMAPCommand.uidSearchBetween(tag: "a1", since: since, before: since)
    XCTAssertEqual(command.body, "UID SEARCH SINCE 06-Aug-2026 BEFORE 06-Aug-2026")
  }

  /// A password containing a quote would otherwise close the string early and
  /// turn the rest of it into command syntax.
  func testQuotingEscapesBackslashesAndQuotes() {
    XCTAssertEqual(IMAPCommand.quoted("plain"), "\"plain\"")
    XCTAssertEqual(IMAPCommand.quoted("a\"b"), "\"a\\\"b\"")
    XCTAssertEqual(IMAPCommand.quoted("a\\b"), "\"a\\\\b\"")

    let command = IMAPCommand.login(tag: "a1", address: "u@e.com", password: "p\"w")
    XCTAssertEqual(command.wireText, "a1 LOGIN \"u@e.com\" \"p\\\"w\"\r\n")
  }

  // MARK: - Framing

  /// Counted over **bytes**, not `Character`s.
  ///
  /// `wireText.filter { $0 == "\n" }.count` was the obvious way to write this
  /// and it is wrong in a way that only shows up on correct output: Swift
  /// iterates a `String` by extended grapheme cluster, and CR LF *is one
  /// cluster*. A correctly framed command therefore contains zero `"\n"`
  /// Characters — the test failed against code that was right, and would have
  /// passed against a command ending in a bare LF, which is the defect it
  /// exists to catch.
  func testEveryCommandEndsCRLFAndNotBareLF() {
    let command = IMAPCommand.logout(tag: "a007")
    XCTAssertTrue(command.wireText.hasSuffix("\r\n"))

    let bytes = Array(command.wireBytes)
    XCTAssertEqual(bytes.filter { $0 == 0x0A }.count, 1)
    XCTAssertEqual(Array(bytes.suffix(2)), [0x0D, 0x0A])
    for (index, byte) in bytes.enumerated() where byte == 0x0A {
      XCTAssertTrue(index > 0 && bytes[index - 1] == 0x0D, "bare LF at byte \(index)")
    }
  }

  /// IDLE is ended by an untagged literal `DONE`. That is the protocol, not an
  /// omission.
  func testIdleIsTerminatedByAnUntaggedDone() {
    XCTAssertEqual(IMAPCommand.idle(tag: "a006").wireText, "a006 IDLE\r\n")
    XCTAssertEqual(IMAPCommand.idleDoneWireText, "DONE\r\n")
  }

  // MARK: - Tags

  /// A tag must be unique for the life of a connection — it is how a response is
  /// matched to the command that caused it.
  func testTagsAreSequentialAndUnique() {
    var generator = IMAPTagGenerator()
    let tags = (0..<5).map { _ in generator.next() }

    XCTAssertEqual(tags, ["a001", "a002", "a003", "a004", "a005"])
    XCTAssertEqual(Set(tags).count, tags.count)
  }
}
