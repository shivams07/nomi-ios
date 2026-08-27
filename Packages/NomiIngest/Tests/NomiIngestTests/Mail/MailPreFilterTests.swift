import Foundation
import NomiCore
import XCTest

@testable import NomiIngest

/// "An email that is not a transaction produces no transaction" (§1.4).
final class MailPreFilterTests: XCTestCase {

  func testFivePromotionalFixturesProduceZeroTransactions() throws {
    let extractor = MailTransactionExtractor()
    XCTAssertGreaterThanOrEqual(MailFixtures.promotionalFixtures.count, 5)

    for file in MailFixtures.promotionalFixtures {
      let outcome = extractor.outcome(for: try MailFixtures.message(file))
      XCTAssertNil(outcome.draft, "\(file) must produce no transaction")
      XCTAssertNil(outcome.layer, file)
    }
  }

  /// Each of the five carries a bank domain AND a currency amount. They are
  /// rejected on the verb, which is the only test that separates
  /// "Get ₹500 cashback" from "₹500 has been debited".
  func testPromotionalFixturesAreRejectedOnTheVerbNotTheDomainOrTheAmount() throws {
    let filter = MailPreFilter()

    for file in MailFixtures.promotionalFixtures {
      let message = try MailFixtures.message(file)
      XCTAssertTrue(filter.isCandidateDomain(message.senderDomain), file)
      XCTAssertNotNil(MailAmount.firstAmount(in: message.extractableText()), file)
      XCTAssertEqual(filter.verdict(for: message), .rejected(.noTransactionVerb), file)
    }
  }

  /// A promo from a domain nobody recognises never reaches an extractor at all,
  /// even though it quotes an amount and uses a verb.
  func testAnUnknownDomainIsDroppedBeforeAnyExtractorRuns() throws {
    let message = try MailFixtures.message("promo_unknown_sender.eml")
    let filter = MailPreFilter()

    XCTAssertEqual(filter.verdict(for: message), .rejected(.unknownDomain))
    XCTAssertNil(MailTransactionExtractor().outcome(for: message).draft)
  }

  /// The gate has to be wider than the pack, or Layer 2 could never run and
  /// `unmatchedSenders` would always be empty.
  func testTheDomainGateIsWiderThanThePack() {
    let filter = MailPreFilter()

    XCTAssertTrue(filter.isCandidateDomain("hdfcbank.net"))          // pack entry
    XCTAssertTrue(filter.isCandidateDomain("alerts.hdfcbank.net"))   // pack subdomain
    XCTAssertTrue(filter.isCandidateDomain("idfcfirstbank.com"))     // candidateDomains
    XCTAssertTrue(filter.isCandidateDomain("bandhanbank.in"))        // token: "bank"
    XCTAssertFalse(filter.isCandidateDomain("shoppingdeals.example"))
    XCTAssertFalse(filter.isCandidateDomain(""))
  }

  /// `credit` on its own cannot be an admission verb: every Indian promo says
  /// "Credit Card". The strong forms and the unambiguous phrases can.
  func testBareCreditIsNotAnAdmissionVerbButTheStrongFormsAre() {
    XCTAssertFalse(MailDirection.containsTransactionVerb("Apply for a Credit Card today"))
    XCTAssertTrue(MailDirection.containsTransactionVerb("Rs 500 has been debited"))
    XCTAssertTrue(MailDirection.containsTransactionVerb("has a debit by transfer of Rs 500"))
  }

  /// …but once a message is already a candidate, bare `debit` resolves the
  /// direction. SBI's alert never uses the -ed form.
  func testBareDebitStillResolvesDirectionOnceAdmitted() {
    XCTAssertEqual(MailDirection.direction(in: "has a debit by transfer of Rs 3,000.00"), .debit)
    XCTAssertEqual(MailDirection.direction(in: "has a credit by transfer of Rs 3,000.00"), .credit)
    XCTAssertNil(MailDirection.direction(in: "your statement is ready"))
  }
}
