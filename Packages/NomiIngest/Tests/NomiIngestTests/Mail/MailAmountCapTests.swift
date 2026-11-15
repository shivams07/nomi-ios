import Foundation
import NomiCore
import XCTest

@testable import NomiIngest

/// B8 mail-amount-cap (Shaun's ruling (b)). An email whose chosen amount is outside
/// `AmountRules`, or overflows `Int`, is ONE needs-review row with amount 0 and reason
/// `.unparseable`, keeping the bank's wording. It is never dropped, and never replaced
/// by another figure from the same mail.
///
/// Expected amounts are hand-checked against the fixture text, in paise:
/// ₹1,00,00,00,000.00 is 100 crore, which is 10^11 paise, the inclusive cap.
final class MailAmountCapTests: XCTestCase {

  // MARK: - Fixture table: in-cap and the cap itself

  /// The cap is inclusive. Exactly 10^11 paise is a real amount and is not flagged by B8.
  func testTheCapItselfIsStoredAsTheAmount() throws {
    let draft = try XCTUnwrap(
      outcome("Rs. 1,00,00,00,000.00 debited from A/c XX4471 on 13-11-26").draft)

    XCTAssertEqual(draft.amountMinor, 100_000_000_000)
    XCTAssertNotEqual(draft.needsReviewReason, .unparseable)
  }

  /// Rs.845.00 is 84,500 paise. The control: the ordinary path is unchanged.
  func testAnOrdinaryRupeeAmountIsUnchanged() throws {
    let result = outcome("Rs.845.00 debited from A/c XX4471 to OLACABS")
    let draft = try XCTUnwrap(result.draft)

    XCTAssertEqual(draft.amountMinor, 84_500)
    XCTAssertFalse(result.wasUnparseableCandidate)
    XCTAssertNotEqual(draft.needsReviewReason, .unparseable)
  }

  // MARK: - Fixture table: one paisa over the cap

  func testOnePaisaOverTheCapInRsFormIsUnparseable() {
    assertUnparseableRow(
      outcome("Rs. 1,00,00,00,000.01 debited from A/c XX4471"), layer: .heuristic)
  }

  func testOnePaisaOverTheCapInINRPrefixIsUnparseable() {
    assertUnparseableRow(
      outcome("INR 1000000000.01 debited from A/c XX4471"), layer: .heuristic)
  }

  func testOnePaisaOverTheCapInRupeeSymbolFormIsUnparseable() {
    assertUnparseableRow(
      outcome("₹1000000000.01 spent on card XX9012"), layer: .heuristic)
  }

  func testOnePaisaOverTheCapInTrailingINRFormIsUnparseable() {
    assertUnparseableRow(
      outcome("1000000000.01 INR debited from A/c XX4471"), layer: .heuristic)
  }

  // MARK: - Overflow

  /// F1. The figure overflows Int, so it used to be dropped and the heuristic took the
  /// balance next to it: Rs 5,000.00 stored as if it were the debit.
  func testOverflowWithAValidBalanceIsUnparseableAndNeverTheBalance() throws {
    let result = outcome(
      "Rs 99999999999999999999.00 debited from A/c XX4471. Avl Bal Rs 5,000.00")

    assertUnparseableRow(result, layer: .heuristic)
    let draft = try XCTUnwrap(result.draft)
    XCTAssertNotEqual(draft.amountMinor, 500_000, "the balance was stored as the debit")
  }

  /// F2. The only rupee figure overflows. The pre-filter must still admit it, or the
  /// message vanishes before any extractor runs.
  func testAnOverflowOnlyRupeeAlertIsAdmittedAndBecomesAnUnparseableRow() {
    let message = alert("INR 99999999999999999999.00 debited")

    XCTAssertEqual(MailPreFilter().verdict(for: message), .candidate)
    assertUnparseableRow(
      MailTransactionExtractor().outcome(for: message), layer: .heuristic)
  }

  /// The same silent drop on the foreign path: an overflowing USD figure with no rupee
  /// figure anywhere. It must be admitted and flagged, not rejected as noCurrencyAmount.
  func testAnOverflowOnlyForeignAlertIsAdmittedAndBecomesAnUnparseableRow() {
    let message = alert("USD 99999999999999999999.00 spent on card XX9012")

    XCTAssertEqual(MailPreFilter().verdict(for: message), .candidate)
    assertUnparseableRow(
      MailTransactionExtractor().outcome(for: message), layer: .heuristic)
  }

  // MARK: - The chosen figure decides

  /// The nearest figure to the verb is over the cap, and an in-cap figure sits further
  /// away in an earlier clause. The chosen figure decides, so the result is unparseable,
  /// not the in-cap 5,000.00.
  func testAnOverCapFigureNearestTheVerbMakesTheRowUnparseable() {
    assertUnparseableRow(
      outcome("Rs 5,000.00 was the available balance. Rs 1,00,00,00,000.01 debited from A/c XX4471."),
      layer: .heuristic)
  }

  // MARK: - Sender pack

  /// Layer 1 captures an over-cap figure. The row is unparseable, and the heuristic is not
  /// consulted: the same mail carries Avl Bal Rs 5,000.00, which the heuristic would take.
  func testASenderPackOverCapAmountIsUnparseableWithoutConsultingTheHeuristic() {
    let result = outcome(
      "Rs. 1,00,00,00,000.01 debited from A/c XX4471. Avl Bal Rs 5,000.00",
      from: "Pack Alerts <alerts@packtest.in>",
      pack: packTestPack)

    assertUnparseableRow(result, layer: .pack)
  }

  /// The pack control: an in-cap figure through the same pack is still read by Layer 1.
  func testASenderPackInCapAmountIsStillReadByLayerOne() throws {
    let result = outcome(
      "Rs. 845.00 debited from A/c XX4471.",
      from: "Pack Alerts <alerts@packtest.in>",
      pack: packTestPack)

    XCTAssertEqual(result.layer, .pack)
    XCTAssertEqual(try XCTUnwrap(result.draft).amountMinor, 84_500)
  }

  // MARK: - Foreign currency over the cap

  /// USD is minor units (cents), so 1,000,000,000.01 USD is 100,000,000,001 and over the
  /// cap. The foreign rule is the same rule.
  func testAForeignAmountOverTheCapIsUnparseable() {
    assertUnparseableRow(
      outcome("USD 1,000,000,000.01 spent on card XX9012"), layer: .heuristic)
  }

  // MARK: - Engine

  /// One over-cap alert through the whole engine. The counts come from the drafts the
  /// pipeline received: one created row, one flagged row, and the amount stored as 0.
  func testOneOverCapAlertReachesThePipelineAsOneFlaggedZeroRow() async throws {
    let pipeline = DraftCountingPipeline()
    let engine = MailSyncEngine(
      fetcher: StubFetcher(messages: [
        alert("Rs. 1,00,00,00,000.01 debited from A/c XX4471 on 13-11-26")
      ]),
      pipeline: pipeline)

    let summary = try await engine.syncNow()

    XCTAssertEqual(summary.flagged, 1)
    XCTAssertEqual(summary.created, 1)
    XCTAssertEqual(pipeline.received.map(\.amountMinor), [0])
    XCTAssertEqual(pipeline.received.first?.needsReviewReason, .unparseable)
  }

  // MARK: - Helpers

  /// A bank the bundled pack does not know, but whose domain is a candidate, so the row
  /// comes from Layer 2 and not from a pack entry.
  private func alert(
    _ body: String,
    from: String = "Bandhan Alerts <alerts@bandhanbank.in>",
    subject: String = "Transaction Alert"
  ) -> MailMessage {
    MailMessage(
      uid: 1, uidValidity: 900_100, fromRaw: from, subject: subject,
      headerDate: MailFixtures.date(2026, 11, 13),
      htmlBody: nil, textBody: body)
  }

  private func outcome(
    _ body: String,
    from: String = "Bandhan Alerts <alerts@bandhanbank.in>",
    pack: SenderPack = .bundled
  ) -> ExtractionOutcome {
    MailTransactionExtractor(pack: pack).outcome(for: alert(body, from: from))
  }

  /// One pack entry for a domain the bundled pack does not hold.
  private var packTestPack: SenderPack {
    let entry = SenderPackEntry(
      senderDomain: "packtest.in",
      bankLabel: "Pack Test",
      subjectPattern: nil,
      fieldRegexes: SenderPackFieldRegexes(
        amount: #"(?:Rs\.?|INR)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)"#,
        date: nil, direction: nil, accountFragment: nil, narration: nil),
      accountHint: nil)
    return SenderPack(
      readme: "", version: 1, candidateDomains: [], candidateDomainTokens: [],
      entries: [entry])
  }

  /// The shape every over-cap case must have: one row, amount 0, flagged, reason
  /// `.unparseable`, from the layer that found the figure.
  private func assertUnparseableRow(
    _ result: ExtractionOutcome,
    layer: ExtractionLayer,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertEqual(result.layer, layer, file: file, line: line)
    XCTAssertTrue(result.wasUnparseableCandidate, file: file, line: line)
    guard let draft = result.draft else {
      XCTFail("expected one unparseable row, got none", file: file, line: line)
      return
    }
    XCTAssertEqual(draft.amountMinor, 0, file: file, line: line)
    XCTAssertTrue(draft.needsReview, file: file, line: line)
    XCTAssertEqual(draft.needsReviewReason, .unparseable, file: file, line: line)
  }
}

/// Counts the way the pipeline counts these drafts: one created row each, and one flagged
/// row for each draft that needs review. The engine adds the batch counts up unchanged.
final class DraftCountingPipeline: DraftIngesting, @unchecked Sendable {
  private(set) var received: [TransactionDraft] = []

  func ingest(_ drafts: [TransactionDraft]) async throws -> IngestBatchResult {
    received += drafts
    return IngestBatchResult(
      created: drafts.count, merged: 0, flagged: drafts.filter(\.needsReview).count)
  }
}
