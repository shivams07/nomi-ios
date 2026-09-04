import Foundation
import NomiCore
import XCTest

@testable import NomiIngest

/// U2's done-when, fixture by fixture.
///
/// **Read this before quoting a green run.** These fixtures are STRUCTURAL —
/// built from publicly documented alert formats, not harvested from a real
/// mailbox (§2.5.1). Passing here means the parser's shape is right. It does
/// NOT mean the amounts are right on Shivam's actual bank mail. R6/R19: the
/// first real backfill is the actual test.
final class MailExtractionFixtureTests: XCTestCase {

  private struct Expected {
    let file: String
    let amountMinor: Int
    let direction: Direction
    let date: Date
    let accountFragmentDigits: String
  }

  private let expectations: [Expected] = [
    Expected(
      file: "sbi_debit_upi.eml", amountMinor: 300_000, direction: .debit,
      date: MailFixtures.date(2026, 8, 12), accountFragmentDigits: "4471"),
    Expected(
      file: "sbi_credit_salary.eml", amountMinor: 8_500_000, direction: .credit,
      date: MailFixtures.date(2026, 7, 31), accountFragmentDigits: "4471"),
    Expected(
      file: "hdfc_debit_split_cells.eml", amountMinor: 450_000, direction: .debit,
      date: MailFixtures.date(2026, 8, 13), accountFragmentDigits: "4471"),
    Expected(
      file: "hdfc_debit_netbanking.eml", amountMinor: 129_950, direction: .debit,
      date: MailFixtures.date(2026, 8, 15), accountFragmentDigits: "4471"),
    Expected(
      file: "icici_debit_nested_split.eml", amountMinor: 234_975, direction: .debit,
      date: MailFixtures.date(2026, 8, 17), accountFragmentDigits: "8812"),
    Expected(
      file: "icici_credit_refund.eml", amountMinor: 120_000, direction: .credit,
      date: MailFixtures.date(2026, 8, 18), accountFragmentDigits: "8812"),
    Expected(
      file: "axis_debit_atm.eml", amountMinor: 500_000, direction: .debit,
      date: MailFixtures.date(2026, 8, 19), accountFragmentDigits: "9930"),
    Expected(
      file: "axis_credit_interest.eml", amountMinor: 41_200, direction: .credit,
      date: MailFixtures.date(2026, 8, 23), accountFragmentDigits: "9930"),
    Expected(
      file: "kotak_debit_card.eml", amountMinor: 199_900, direction: .debit,
      date: MailFixtures.date(2026, 8, 24), accountFragmentDigits: "5540"),
    Expected(
      file: "kotak_debit_upi_nbsp.eml", amountMinor: 75_025, direction: .debit,
      date: MailFixtures.date(2026, 8, 25), accountFragmentDigits: "5540"),
  ]

  // MARK: - >= 10 structural fixtures, >= 2 per provisional pack entry

  func testTenStructuralFixturesCoverTwoPerProvisionalPackEntry() throws {
    XCTAssertGreaterThanOrEqual(expectations.count, 10)

    var perDomain: [String: Int] = [:]
    for expected in expectations {
      let message = try MailFixtures.message(expected.file)
      perDomain[message.senderDomain, default: 0] += 1
    }
    for entry in SenderPack.bundled.entries {
      let matching = perDomain.filter { $0.key.hasSuffix(entry.senderDomain) }
        .values.reduce(0, +)
      XCTAssertGreaterThanOrEqual(
        matching, 2, "\(entry.senderDomain) needs at least 2 fixtures")
    }
  }

  func testEveryStructuralFixtureExtractsDateAmountDirectionAndAccountFragment() throws {
    let extractor = MailTransactionExtractor()

    for expected in expectations {
      let message = try MailFixtures.message(expected.file)
      let outcome = extractor.outcome(for: message)

      XCTAssertEqual(outcome.layer, .pack, "\(expected.file) should hit Layer 1")
      XCTAssertFalse(outcome.wasUnparseableCandidate, expected.file)

      let draft = try XCTUnwrap(outcome.draft, expected.file)
      XCTAssertEqual(draft.amountMinor, expected.amountMinor, expected.file)
      XCTAssertEqual(draft.direction, expected.direction, expected.file)
      XCTAssertEqual(draft.date, expected.date, expected.file)
      XCTAssertEqual(draft.source, .email, expected.file)
      XCTAssertEqual(draft.currencyCode, "INR", expected.file)

      // The account fragment is read, but it resolves to no account because
      // nothing has been learned yet — §1.2 flags rather than guesses.
      XCTAssertNil(draft.accountID, expected.file)
      XCTAssertTrue(draft.needsReview, expected.file)
    }
  }

  /// The fragment reaches the binding resolver, which is the seam U8 fills in.
  func testTheAccountFragmentIsWhatReachesTheBindingResolver() throws {
    for expected in expectations {
      let recorder = RecordingBindings()
      let extractor = MailTransactionExtractor(bindings: recorder)
      let message = try MailFixtures.message(expected.file)

      _ = extractor.outcome(for: message)

      XCTAssertEqual(
        recorder.lastFragment, expected.accountFragmentDigits,
        "\(expected.file) should offer its card/account fragment for binding")
      XCTAssertEqual(recorder.lastDomain, message.senderDomain, expected.file)
    }
  }

  /// Once a binding exists, the draft carries the account and stops being
  /// review-worthy on that ground.
  func testAKnownBindingResolvesTheAccountAndClearsTheReviewFlag() throws {
    let accountID = UUID()
    let extractor = MailTransactionExtractor(bindings: FixedBinding(accountID))
    let message = try MailFixtures.message("hdfc_debit_netbanking.eml")

    let draft = try XCTUnwrap(extractor.outcome(for: message).draft)

    XCTAssertEqual(draft.accountID, accountID)
    XCTAssertFalse(draft.needsReview)
  }

  /// The epoch is not a date, it is "the Date: header was unreadable". A row
  /// that reaches the fallback has to say so, or it sorts to the bottom of a
  /// ledger ordered by date and is never looked at again.
  ///
  /// Layer 1 with a resolved binding is the only path that would otherwise
  /// produce `needsReview == false`, which is why the binding is fixed here.
  func testAnUnreadableDateHeaderFlagsTheRowEvenWhenTheAccountResolves() throws {
    let extractor = MailTransactionExtractor(bindings: FixedBinding(UUID()))
    let message = try MailFixtures.message("hdfc_debit_unreadable_date.eml")

    let draft = try XCTUnwrap(extractor.outcome(for: message).draft)

    XCTAssertEqual(draft.date, Date(timeIntervalSince1970: 0), "no date was readable anywhere")
    XCTAssertNotNil(draft.accountID)
    XCTAssertTrue(draft.needsReview, "a 1970 row must be visible, not silently filed")
  }

  // MARK: - R6: the amount split across nested table cells

  /// The failure mode a hand-built fixture is most likely to omit, and the one
  /// R6 says produces plausible-and-wrong amounts. Two fixtures, two shapes.
  func testTwoFixturesSplitTheAmountAcrossNestedTableCells() throws {
    let extractor = MailTransactionExtractor()

    // Currency symbol, rupees and paise each in their own <td>.
    let hdfc = try MailFixtures.message("hdfc_debit_split_cells.eml")
    XCTAssertTrue(
      hdfc.htmlBody?.contains(#"<td align="right">₹</td>"#) == true,
      "fixture must actually keep the symbol in its own cell")
    XCTAssertEqual(try XCTUnwrap(extractor.outcome(for: hdfc).draft).amountMinor, 450_000)

    // Nested tables, and the paise in a cell that opens with the decimal point.
    let icici = try MailFixtures.message("icici_debit_nested_split.eml")
    XCTAssertTrue(
      icici.htmlBody?.contains(#"<td nowrap>. 75</td>"#) == true,
      "fixture must actually keep the paise in its own cell")
    XCTAssertEqual(try XCTUnwrap(extractor.outcome(for: icici).draft).amountMinor, 234_975)
  }

  // MARK: - §2.4: merchant fields are not this unit's output

  func testNoFixtureProducesMerchantFieldsBecauseThePipelineDerivesThem() throws {
    let extractor = MailTransactionExtractor()

    for file in MailFixtures.packFixtures + ["unknown_bank_layer2.eml"] {
      let draft = try XCTUnwrap(
        extractor.outcome(for: try MailFixtures.message(file)).draft, file)
      XCTAssertNil(draft.merchantName, file)
      XCTAssertNil(draft.upiKindRaw, file)
      XCTAssertNil(draft.counterpartyVPA, file)
    }
  }

  /// U2 emits the raw narration; U4 parses it. The UPI reference is carried
  /// through verbatim rather than reduced to a merchant name.
  func testUPINarrationIsCarriedThroughUnparsed() throws {
    let extractor = MailTransactionExtractor()
    let draft = try XCTUnwrap(
      extractor.outcome(for: try MailFixtures.message("kotak_debit_upi_nbsp.eml")).draft)

    XCTAssertEqual(draft.descriptionText, "UPI-ZOMATO-zomato@paytm-9931204411")
    XCTAssertNil(draft.merchantName)
  }

  // MARK: - Determinism (§1.5)

  func testExtractionIsDeterministicAcrossRepeatedRuns() throws {
    let extractor = MailTransactionExtractor(now: { Date(timeIntervalSince1970: 0) })

    for file in MailFixtures.packFixtures {
      let message = try MailFixtures.message(file)
      let first = try XCTUnwrap(extractor.outcome(for: message).draft, file)
      let second = try XCTUnwrap(extractor.outcome(for: message).draft, file)
      XCTAssertEqual(first, second, file)
    }
  }

  func testExternalIDCarriesMailboxAndUIDValidityNotJustTheUID() throws {
    let message = try MailFixtures.message("axis_debit_atm.eml", uid: 4242)
    XCTAssertEqual(message.externalID, "INBOX/900100/4242")
  }
}

// MARK: - Test doubles

private final class RecordingBindings: AccountBindingResolving, @unchecked Sendable {
  private(set) var lastDomain: String?
  private(set) var lastFragment: String?

  func accountID(senderDomain: String, cardFragment: String) -> UUID? {
    lastDomain = senderDomain
    lastFragment = cardFragment
    return nil
  }
}

private struct FixedBinding: AccountBindingResolving {
  let bound: UUID
  init(_ bound: UUID) { self.bound = bound }
  func accountID(senderDomain: String, cardFragment: String) -> UUID? { bound }
}
