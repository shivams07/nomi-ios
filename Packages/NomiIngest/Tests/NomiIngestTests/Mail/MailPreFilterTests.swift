import Foundation
import NomiCore
import XCTest

@testable import NomiIngest

/// "An email that is not a transaction produces no transaction" (§1.4).
final class MailPreFilterTests: XCTestCase {

  /// The promotions this unit adds, and the reason it exists: every one of them
  /// passes ALL THREE positive conditions - a bank domain, a currency amount and
  /// a transaction verb that survives word-boundary matching. Nothing the
  /// pre-filter can currently test separates them from a real alert.
  ///
  /// They are held here rather than appended to `MailFixtures.promotionalFixtures`
  /// because that file belongs to `mail-extraction-accuracy`, and because the
  /// existing list carries a different claim - those five are rejected on the
  /// verb, these seven get past it.
  static let promotionsPastTheVerbGate = [
    "promo_hdfc_cashback_credited.eml",
    "promo_sbi_preapproved_loan.eml",
    "promo_icici_emi_conversion.eml",
    "promo_kotak_prepaid_wallet.eml",
    "promo_hdfc_bill_payment.eml",
    "promo_axis_reward_points.eml",
    "promo_axis_fee_waiver.eml",
  ]

  /// FAILS before the fourth condition exists. All seven are admitted today.
  ///
  /// The three positive conditions are asserted first and individually so that a
  /// failure below reads as "the gate admitted a promotion" and never as "the
  /// fixture was built wrong".
  func testPromotionsThatPassAllThreePositiveConditionsAreStillRejected() throws {
    let filter = MailPreFilter()

    for file in Self.promotionsPastTheVerbGate {
      let message = try MailFixtures.message(file)
      let haystack = message.extractableText() + " " + message.subject

      XCTAssertTrue(filter.isCandidateDomain(message.senderDomain), "domain: \(file)")
      XCTAssertNotNil(MailAmount.firstAmount(in: haystack), "amount: \(file)")
      XCTAssertTrue(MailDirection.containsTransactionVerb(haystack), "verb: \(file)")

      XCTAssertFalse(filter.isCandidate(message), "admitted: \(file)")
      XCTAssertNil(MailTransactionExtractor().outcome(for: message).draft, "draft: \(file)")
    }
  }

  /// The reason, not just the outcome. `SyncSummary` is what tells us whether
  /// this gate is too tight, and it can only do that if a promotion rejected on
  /// the vocabulary is distinguishable from one that never had a verb.
  func testPromotionsRejectedByTheFourthConditionSaySo() throws {
    let filter = MailPreFilter()

    for file in Self.promotionsPastTheVerbGate {
      let message = try MailFixtures.message(file)
      XCTAssertEqual(filter.verdict(for: message), .rejected(.promotional), file)
    }
  }

  /// The vocabulary is DATA (design point 3), so this asserts it actually came
  /// off `senders.json` and is not a Swift literal that happens to work.
  func testTheVocabularyIsLoadedFromTheResource() {
    let phrases = MailPreFilter().promotionalPhrases

    XCTAssertFalse(phrases.isEmpty, "promotionalPhrases missing from senders.json")
    let fromTheDesign = [
      "offer", "cashback", "apply now", "T&C", "limited period", "pre-approved",
      "congratulations",
    ]
    for expected in fromTheDesign {
      XCTAssertTrue(phrases.contains(expected), "missing phrase: " + expected)
    }
  }

  /// A vocabulary entry that matches nothing is invisible: the gate compiles,
  /// the fixtures still pass on the OTHER entries, and the dead phrase sits
  /// there forever looking like coverage. Assert over the whole set, never
  /// per phrase - the same trap a glob-pattern seed walks into.
  func testEveryPromotionalPhraseMatchesItself() {
    let filter = MailPreFilter()

    for phrase in filter.promotionalPhrases {
      XCTAssertFalse(phrase.isEmpty, "empty phrase in promotionalPhrases")
      XCTAssertTrue(
        filter.containsPromotionalLanguage("Dear customer, " + phrase + " today."),
        "dead promo phrase: " + phrase)
    }
  }

  /// Word boundaries here too. `offer` must not fire on `offered`, and the
  /// vocabulary must not reject an alert for quoting a merchant.
  func testPromotionalPhrasesDoNotFireInsideLongerWords() {
    let filter = MailPreFilter()

    XCTAssertFalse(filter.containsPromotionalLanguage("Rs.500 was offered and debited"))
    XCTAssertFalse(filter.containsPromotionalLanguage("Paid Rs.240 to CASHBACKERS PVT LTD"))
    XCTAssertTrue(filter.containsPromotionalLanguage("Get Rs.500 cashback"))
  }

  /// The cost side of the trade, asserted rather than assumed. A negative
  /// condition can only be wrong in one expensive way - rejecting real mail -
  /// and it fails silently when it does.
  func testNoExistingBankFixtureIsRejectedAsPromotional() throws {
    let filter = MailPreFilter()
    let files =
      MailFixtures.packFixtures + ["unknown_bank_layer2.eml", "unparseable_candidate.eml"]

    for file in files {
      let verdict = filter.verdict(for: try MailFixtures.message(file))
      XCTAssertNotEqual(verdict, .rejected(.promotional), file)
    }
  }

  /// A `senders.json` with no `promotionalPhrases` key must degrade to "reject
  /// nothing", never to "reject everything" and never to a pack that fails to
  /// decode at all - which would take the domain gate down with it.
  func testAMissingVocabularyRejectsNothing() throws {
    let pack = SenderPack(
      readme: "", version: 1,
      candidateDomains: ["hdfcbank.net"], candidateDomainTokens: [],
      promotionalPhrases: nil, entries: [])
    let filter = MailPreFilter(pack: pack)

    XCTAssertTrue(filter.promotionalPhrases.isEmpty)
    XCTAssertFalse(filter.containsPromotionalLanguage("Get Rs.500 cashback, T&C apply"))
    XCTAssertEqual(
      filter.verdict(for: try MailFixtures.message("promo_hdfc_cashback_credited.eml")),
      .candidate,
      "a missing vocabulary must disable the gate, not the filter")
  }

  /// Six promo fixtures existed at `92d90c5`, so "at least six" would have been
  /// satisfied by adding none. This asserts the new floor, and - the half that
  /// matters more - that every promo file on disk is named in one of the three
  /// lists. A fixture nothing asserts against is worse than no fixture: the
  /// directory listing implies a coverage that does not exist.
  func testEveryPromoFixtureOnDiskIsAssertedAgainst() throws {
    let directory = MailFixtures.url("promo_unknown_sender.eml").deletingLastPathComponent()
    let onDisk = try FileManager.default.contentsOfDirectory(atPath: directory.path)
      .filter { $0.hasPrefix("promo_") && $0.hasSuffix(".eml") }

    XCTAssertGreaterThanOrEqual(onDisk.count, 12, "promo fixtures on disk")

    let asserted = Set(
      MailFixtures.promotionalFixtures + Self.promotionsPastTheVerbGate
        + ["promo_unknown_sender.eml"])
    XCTAssertEqual(
      Set(onDisk).subtracting(asserted), [], "promo fixtures nothing asserts against")
  }

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

  /// Substring matching admits three whole classes of non-transaction mail:
  /// `prepaid`/`postpaid` card marketing, `recharged` telecom and wallet
  /// promos, and `unpaid` dues reminders. All three hold a bank domain and an
  /// amount, so the verb is the only gate left standing — and it lets them
  /// through. The fix is `\bpaid\b`, never `contains("paid")`.
  func testTransactionVerbsMatchOnWordBoundariesNotSubstrings() {
    XCTAssertFalse(MailDirection.containsTransactionVerb("Your prepaid card is ready"))
    XCTAssertFalse(MailDirection.containsTransactionVerb("Recharged successfully for Rs.399"))
    XCTAssertFalse(MailDirection.containsTransactionVerb("Amount unpaid: Rs.1,240"))
  }

  /// The other half of the same change: narrowing to word boundaries must not
  /// cost a single real alert.
  func testWordBoundaryMatchingStillAdmitsRealAlerts() {
    XCTAssertTrue(MailDirection.containsTransactionVerb("Rs.500 has been debited"))
    XCTAssertTrue(MailDirection.containsTransactionVerb("You have paid Rs.500 to Swiggy"))
    XCTAssertTrue(MailDirection.containsTransactionVerb("has a debit by transfer of Rs 500"))
    XCTAssertTrue(MailDirection.containsTransactionVerb("A transaction of Rs.500 was made"))
  }

  /// …but once a message is already a candidate, bare `debit` resolves the
  /// direction. SBI's alert never uses the -ed form.
  func testBareDebitStillResolvesDirectionOnceAdmitted() {
    XCTAssertEqual(MailDirection.direction(in: "has a debit by transfer of Rs 3,000.00"), .debit)
    XCTAssertEqual(MailDirection.direction(in: "has a credit by transfer of Rs 3,000.00"), .credit)
    XCTAssertNil(MailDirection.direction(in: "your statement is ready"))
  }
}
