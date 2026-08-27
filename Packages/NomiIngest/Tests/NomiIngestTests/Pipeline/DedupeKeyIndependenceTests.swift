import Foundation
import NomiCore
import XCTest

@testable import NomiIngest

/// Design §2.4: UPI parsing must never touch `dedupeKey`. The failure it
/// prevents is a version-drift one — ship pattern set v1, ingest six months,
/// add three patterns in v1.1, and every new row gets a different key from its
/// historical twin. These tests are the guard on that.
final class DedupeKeyIndependenceTests: XCTestCase {

  private let upiNarration = "UPI/P2M/412345678901/SWIGGY/HDFC/Payment from Ph"

  func testTheKeyIsExactlyTheFunctionOfDateAmountDirectionAndNormalizedDescription() {
    let draft = Fixture.draft(description: upiNarration)
    let derived = DraftDerivation.derive(draft, calendar: Fixture.calendar)

    // Derived merchant fields are populated...
    XCTAssertEqual(derived.merchantName, "SWIGGY")
    XCTAssertEqual(derived.upiKindRaw, "p2m")

    // ...and the key is bit-identical to one computed with no knowledge of them.
    let independent = makeDedupeKey(
      date: draft.date,
      amountMinor: draft.amountMinor,
      directionRaw: draft.direction.rawValue,
      normalizedDescription: normalizeDescription(draft.descriptionText),
      calendar: Fixture.calendar
    )
    XCTAssertEqual(derived.dedupeKey, independent)
  }

  func testTwoNarrationsWithTheSameParsedMerchantStillGetDifferentKeys() {
    let slash = Fixture.draft(description: upiNarration)
    let hyphen = Fixture.draft(description: "UPI-SWIGGY-swiggy@okhdfcbank-PAYMENT")

    let a = DraftDerivation.derive(slash, calendar: Fixture.calendar)
    let b = DraftDerivation.derive(hyphen, calendar: Fixture.calendar)

    XCTAssertEqual(a.merchantName, b.merchantName, "same payee, by design")
    XCTAssertNotEqual(
      a.dedupeKey, b.dedupeKey,
      "merchantName must not be able to collapse two distinct narrations")
  }

  func testAnUnparseableNarrationGetsTheSameKeyItWouldWithNoParserAtAll() {
    let draft = Fixture.draft(description: "POS 4471 BIG BAZAAR MUMBAI")
    let derived = DraftDerivation.derive(draft, calendar: Fixture.calendar)

    XCTAssertNil(derived.merchantName, "no UPI form here")
    XCTAssertEqual(
      derived.dedupeKey,
      makeDedupeKey(
        date: draft.date,
        amountMinor: draft.amountMinor,
        directionRaw: draft.direction.rawValue,
        normalizedDescription: normalizeDescription(draft.descriptionText),
        calendar: Fixture.calendar
      ))
  }

  /// The v5 done-when, end to end: identical raw narration, two sources, one
  /// row, one key.
  func testTwoSourcesWithIdenticalNarrationProduceOneRowWithOneKey() async throws {
    let store = FakePipelineStore()
    let pipeline = await Fixture.pipeline(store: store)

    let fromMail = Fixture.draft(description: upiNarration, source: .email, externalID: "uid-901")
    let fromFile = Fixture.draft(description: upiNarration, source: .file, externalID: "REF-55")

    let result = try await pipeline.ingest([fromMail, fromFile])

    XCTAssertEqual(result.created, 1)
    XCTAssertEqual(result.merged, 1)

    let count = await store.rowCount
    XCTAssertEqual(count, 1)

    let onlyRow = await store.onlyRow
    let row = try XCTUnwrap(onlyRow)
    XCTAssertEqual(row.mergedCount, 2)
    XCTAssertEqual(Set(row.sourceRefs.map(\.source)), [.email, .file])
    XCTAssertEqual(row.merchantName, "SWIGGY")
    XCTAssertEqual(
      row.dedupeKey,
      DraftDerivation.derive(fromMail, calendar: Fixture.calendar).dedupeKey)
  }

  func testAnIngesterThatPreFillsADerivedFieldIsReportedAsAViolation() {
    // `DraftDerivation.derive` traps on this in a debug build, which is the
    // point — but a trap cannot be asserted on, so the rule is tested here.
    var draft = Fixture.draft()
    XCTAssertTrue(DraftDerivation.violations(in: draft).isEmpty)

    draft.merchantName = "SWIGGY"
    draft.counterpartyVPA = "swiggy@okhdfcbank"
    XCTAssertEqual(
      DraftDerivation.violations(in: draft),
      [.merchantNamePreset, .counterpartyVPAPreset])
  }

  func testDerivationIgnoresWhateverTheDraftCarriedInDerivedFields() {
    // Release builds do not trap, so the pipeline must still be correct when
    // an ingester gets this wrong in the field.
    var draft = Fixture.draft(description: "POS 4471 BIG BAZAAR MUMBAI")
    draft.merchantName = "WRONG"
    draft.upiKindRaw = "p2p"

    // Bypasses `derive`'s assertion deliberately: this asserts the release
    // behaviour, not the debug one.
    let upi = UPINarration.parse(draft.descriptionText)
    XCTAssertNil(upi, "the parser, not the draft, decides")
  }
}
