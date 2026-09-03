import Foundation
import NomiCore
import XCTest

@testable import NomiIngest

/// Layer 2, the safety net, and the measurement that replaced the question
/// nobody was willing to ask (§1.4, §2.5.1).
final class MailLayerTwoTests: XCTestCase {

  private let unknownBank = "unknown_bank_layer2.eml"
  private let runningBalance = "unknown_bank_running_balance.eml"

  func testASenderWithNoPackEntryStillYieldsATransactionViaLayerTwo() throws {
    let message = try MailFixtures.message(unknownBank)
    XCTAssertNil(
      SenderPack.bundled.entry(forDomain: message.senderDomain, subject: message.subject),
      "the fixture must genuinely have no pack entry, or this proves nothing")

    let outcome = MailTransactionExtractor().outcome(for: message)

    XCTAssertEqual(outcome.layer, .heuristic)
    let draft = try XCTUnwrap(outcome.draft)
    XCTAssertEqual(draft.amountMinor, 215_000)
    XCTAssertEqual(draft.direction, .debit)
    // Recall with a human gate: every Layer-2 row is flagged, always.
    XCTAssertTrue(draft.needsReview)
  }

  func testLayerTwoIncrementsHeuristicMatchedAndLayerOneDoesNot() async throws {
    let messages = try [unknownBank, "hdfc_debit_netbanking.eml"].enumerated()
      .map { try MailFixtures.message($1, uid: UInt32($0 + 1)) }

    let summary = try await syncSummary(over: messages)

    XCTAssertEqual(summary.heuristicMatched, 1)
    XCTAssertEqual(summary.packMatched, 1)
    XCTAssertEqual(summary.scanned, 2)
  }

  // MARK: - The running balance in the next cell

  /// FAILS today. Two sibling `<td>`s: the transaction in one, the running
  /// balance in the next. `text()` joins siblings with a single space and no
  /// sentence terminator, so `clauseAroundFirstAmount` runs straight past the
  /// cell boundary and the narration swallows "Available Balance".
  func testTheNarrationStopsAtTheCellBoundaryAndExcludesTheRunningBalance() throws {
    let message = try MailFixtures.message(runningBalance)
    let draft = try XCTUnwrap(MailTransactionExtractor().outcome(for: message).draft)

    XCTAssertFalse(
      draft.descriptionText.lowercased().contains("balance"),
      "narration ran into the next cell: " + draft.descriptionText)
  }

  /// FAILS today. Largest-wins picks Rs.48,900.00 — the balance — over the
  /// Rs.3,275.50 that was actually spent. A plausible, wrong number is R6's
  /// worst outcome, and it is the reason Layer 2's amount rule has to be about
  /// where the verb is rather than which number is biggest.
  func testLayerTwoTakesTheTransactionAmountNotTheLargerRunningBalance() throws {
    let message = try MailFixtures.message(runningBalance)
    let draft = try XCTUnwrap(MailTransactionExtractor().outcome(for: message).draft)

    XCTAssertEqual(draft.amountMinor, 327_550, "3,275.50 is the transaction")
    XCTAssertNotEqual(draft.amountMinor, 4_890_000, "48,900.00 is the balance")
  }

  // MARK: - unmatchedSenders: domain only, never an address

  func testTheLayerTwoMessageContributesItsDomainToUnmatchedSenders() async throws {
    let message = try MailFixtures.message(unknownBank)
    let summary = try await syncSummary(over: [message])

    XCTAssertEqual(summary.unmatchedSenders.map(\.domain), ["bandhanbank.in"])
    XCTAssertEqual(summary.unmatchedSenders.first?.count, 1)
  }

  /// The privacy rule from §2.5.1, asserted rather than assumed: the full
  /// address appears nowhere in the summary, and neither does the subject.
  func testTheFullAddressAndSubjectAppearNowhereInTheSummary() async throws {
    let message = try MailFixtures.message(unknownBank)
    XCTAssertEqual(message.senderAddress, "alerts@bandhanbank.in")

    let summary = try await syncSummary(over: [message])
    let rendered = summary.unmatchedSenders.map { "\($0.domain)|\($0.count)" }.joined()

    XCTAssertFalse(rendered.contains(message.senderAddress))
    XCTAssertFalse(rendered.contains("alerts@"))
    XCTAssertFalse(rendered.contains(message.subject))
  }

  func testUnmatchedSendersRanksByCountAndCapsAtTen() {
    var tally = UnmatchedSenderTally()
    for index in 0..<12 {
      let message = makeMessage(domain: "bank\(index).example")
      for _ in 0...index { tally.record(message) }
    }

    let top = tally.top()
    XCTAssertEqual(top.count, 10)
    XCTAssertEqual(top.first?.domain, "bank11.example")
    XCTAssertEqual(top.first?.count, 12)
    XCTAssertEqual(top.map(\.count), top.map(\.count).sorted(by: >))
  }

  /// Equal counts break alphabetically, so two syncs over the same mail report
  /// the same order. A report that reshuffles every run is a report nobody
  /// trusts.
  func testEqualCountsBreakDeterministically() {
    var tally = UnmatchedSenderTally()
    for domain in ["zeta.bank", "alpha.bank", "mid.bank"] {
      tally.record(makeMessage(domain: domain))
    }
    XCTAssertEqual(tally.top().map(\.domain), ["alpha.bank", "mid.bank", "zeta.bank"])
  }

  // MARK: - The unparseable candidate

  /// A genuine candidate — bank domain, an amount in the subject, a verb — whose
  /// body carries nothing readable. §1.4's safety net: ONE flagged row, not a
  /// silent miss and not a guessed amount.
  func testAnUnparseableCandidateProducesExactlyOneNeedsReviewTransaction() throws {
    let message = try MailFixtures.message("unparseable_candidate.eml")
    let outcome = MailTransactionExtractor().outcome(for: message)

    XCTAssertTrue(outcome.wasUnparseableCandidate)
    let draft = try XCTUnwrap(outcome.draft)
    XCTAssertTrue(draft.needsReview)
    // Zero, not a plausible guess. R6's worst failure is a wrong number that
    // looks right; the review queue shows the raw source instead.
    XCTAssertEqual(draft.amountMinor, 0)
    XCTAssertNil(draft.accountID)
  }

  func testAnUnparseableCandidateProducesOneDraftAndNotTwo() async throws {
    let message = try MailFixtures.message("unparseable_candidate.eml")
    let pipeline = RecordingPipeline()
    let engine = MailSyncEngine(
      fetcher: StubFetcher(messages: [message]), pipeline: pipeline)

    _ = try await engine.syncNow()

    XCTAssertEqual(pipeline.received.count, 1)
    XCTAssertEqual(pipeline.received.first?.count, 1)
  }

  // MARK: -

  private func syncSummary(over messages: [MailMessage]) async throws -> SyncSummary {
    let engine = MailSyncEngine(
      fetcher: StubFetcher(messages: messages), pipeline: RecordingPipeline())
    return try await engine.syncNow()
  }

  private func makeMessage(domain: String) -> MailMessage {
    MailMessage(
      uid: 1, uidValidity: 1, fromRaw: "Alerts <alerts@\(domain)>",
      subject: "Transaction Alert", headerDate: Date(timeIntervalSince1970: 0),
      htmlBody: nil, textBody: "")
  }
}
