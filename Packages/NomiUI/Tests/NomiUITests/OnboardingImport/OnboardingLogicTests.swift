import Foundation
import NomiCore
import XCTest
@testable import NomiUI

final class OnboardingLogicTests: XCTestCase {
  func testGmailHasFixedHost() {
    XCTAssertEqual(MailProvider.gmail.fixedHost, "imap.gmail.com")
  }

  func testICloudHasFixedHost() {
    XCTAssertEqual(MailProvider.icloud.fixedHost, "imap.mail.me.com")
  }

  func testZohoHasFixedHost() {
    XCTAssertEqual(MailProvider.zoho.fixedHost, "imap.zoho.in")
  }

  func testGenericHasNoFixedHost() {
    XCTAssertNil(MailProvider.generic.fixedHost)
  }

  func testConnectFormRequiresAddressAndPassword() {
    XCTAssertFalse(ConnectFormGate.isValid(provider: .gmail, address: "", host: "", password: "secret"))
    XCTAssertFalse(ConnectFormGate.isValid(provider: .gmail, address: "a@b.com", host: "", password: ""))
  }

  func testConnectFormValidForFixedHostProviderWithoutHostEntry() {
    XCTAssertTrue(ConnectFormGate.isValid(provider: .gmail, address: "a@b.com", host: "", password: "secret"))
  }

  func testConnectFormRequiresHostForGenericProvider() {
    XCTAssertFalse(ConnectFormGate.isValid(provider: .generic, address: "a@b.com", host: "", password: "secret"))
    XCTAssertTrue(ConnectFormGate.isValid(provider: .generic, address: "a@b.com", host: "mail.example.com", password: "secret"))
  }

  func testMailErrorMessagesAreNamedNotGeneric() {
    XCTAssertTrue(MailErrorMessage.text(for: .authenticationFailed).lowercased().contains("password"))
    XCTAssertTrue(MailErrorMessage.text(for: .connectionFailed).lowercased().contains("connection") || MailErrorMessage.text(for: .connectionFailed).lowercased().contains("reach"))
  }

  func testUnknownMailErrorFallsBackWhenDetailIsEmpty() {
    XCTAssertFalse(MailErrorMessage.text(for: .unknown("")).isEmpty)
  }

  func testUnknownMailErrorUsesDetailWhenPresent() {
    XCTAssertEqual(MailErrorMessage.text(for: .unknown("IMAP timeout")), "IMAP timeout")
  }

  func testBackfillFractionClampsBetweenZeroAndOne() {
    XCTAssertEqual(BackfillMath.fraction(BackfillProgress(scanned: 0, total: 0, created: 0)), 0)
    XCTAssertEqual(BackfillMath.fraction(BackfillProgress(scanned: 50, total: 100, created: 5)), 0.5, accuracy: 0.0001)
    XCTAssertEqual(BackfillMath.fraction(BackfillProgress(scanned: 150, total: 100, created: 5)), 1)
  }

  func testBackfillCompleteOnlyWhenScannedReachesTotal() {
    XCTAssertFalse(BackfillMath.isComplete(BackfillProgress(scanned: 99, total: 100, created: 0)))
    XCTAssertTrue(BackfillMath.isComplete(BackfillProgress(scanned: 100, total: 100, created: 0)))
    XCTAssertFalse(BackfillMath.isComplete(BackfillProgress(scanned: 0, total: 0, created: 0)))
  }

  func testBackfillCompletionSummaryReportsCountersAsPlainCopy() {
    let summary = SyncSummary(scanned: 1200, created: 91, merged: 4, flagged: 6, packMatched: 70, heuristicMatched: 21, unmatchedSenders: [])
    let lines = BackfillCompletionSummary.lines(for: summary)
    XCTAssertTrue(lines.contains("1200 emails scanned"))
    XCTAssertTrue(lines.contains("91 transactions found"))
    XCTAssertTrue(lines.contains("70 matched a known bank format, 21 matched generically"))
  }

  func testBackfillCompletionSummaryOmitsUnmatchedLineWhenNoneUnmatched() {
    let summary = SyncSummary(scanned: 1200, created: 91, merged: 4, flagged: 6, packMatched: 70, heuristicMatched: 21, unmatchedSenders: [])
    let lines = BackfillCompletionSummary.lines(for: summary)
    XCTAssertFalse(lines.contains { $0.contains("Not matched") })
  }

  func testBackfillCompletionSummaryNamesEveryUnmatchedDomainAndCount() {
    let unmatched = [
      UnmatchedSender(domain: "chase.com", count: 3),
      UnmatchedSender(domain: "boa.com", count: 1),
    ]
    let summary = SyncSummary(scanned: 1200, created: 91, merged: 4, flagged: 6, packMatched: 70, heuristicMatched: 21, unmatchedSenders: unmatched)
    let lines = BackfillCompletionSummary.lines(for: summary)
    let unmatchedLine = lines.first { $0.contains("Not matched") }
    XCTAssertNotNil(unmatchedLine)
    for sender in unmatched {
      XCTAssertTrue(unmatchedLine!.contains("\(sender.domain) (\(sender.count))"))
    }
  }

  func testBackfillCompletionSummaryNeverEmitsAnAddress() {
    let unmatched = [
      UnmatchedSender(domain: "chase.com", count: 3),
      UnmatchedSender(domain: "boa.com", count: 1),
    ]
    let summary = SyncSummary(scanned: 1200, created: 91, merged: 4, flagged: 6, packMatched: 70, heuristicMatched: 21, unmatchedSenders: unmatched)
    let lines = BackfillCompletionSummary.lines(for: summary)
    XCTAssertFalse(lines.contains { $0.contains("@") })
  }
}
