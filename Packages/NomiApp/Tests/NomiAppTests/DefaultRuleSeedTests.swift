import Foundation
import NomiCore
import NomiIngest
import XCTest

@testable import NomiApp

/// The starter rule set is *content*, and content is what a compiler cannot
/// check. `DefaultRuleSeed.apply` touches `@Model`; the specs it inserts do not,
/// and everything that can be wrong about this seed is in the specs.
final class DefaultRuleSeedTests: XCTestCase {

  private var specs: [RuleSeedSpec] { DefaultRuleSeed.specs }

  // MARK: - Idempotence

  /// Seeding is idempotent by *identity*. `Rule` is a SwiftData model on a
  /// CloudKit-backed store: two devices on one iCloud account each seed on their
  /// own first launch, and there is no reconcile pass for rules, so a second
  /// application producing anything at all is two of every rule forever.
  func testASecondApplicationSeedsNothing() {
    let afterFirst = Set(DefaultRuleSeed.missing(existingIDs: []).map(\.id))
    XCTAssertEqual(afterFirst.count, specs.count, "the first application seeds everything")

    XCTAssertTrue(
      DefaultRuleSeed.missing(existingIDs: afterFirst).isEmpty,
      "a second application must seed nothing")
  }

  /// The partial case, which is the one that actually happens: a store restored
  /// from a backup that predates a rule being added, or a device that synced
  /// half the set. Only the gap heals, and it heals to exactly the gap.
  func testOnlyTheMissingRulesAreSeededBack() {
    let held = Set(specs.dropLast(3).map(\.id))
    let missing = DefaultRuleSeed.missing(existingIDs: held)

    XCTAssertEqual(missing.map(\.id), specs.suffix(3).map(\.id))
  }

  func testIDsAreUniqueAndDoNotCollideWithTheCategorySeed() {
    XCTAssertEqual(Set(specs.map(\.id)).count, specs.count)

    let categoryIDs = Set(DefaultCategorySeed.specs.map(\.id))
    XCTAssertTrue(Set(specs.map(\.id)).isDisjoint(with: categoryIDs))
  }

  // MARK: - Every rule targets a real seeded category

  /// A rule pointing at a `categoryID` that no row has is a rule that
  /// categorises a transaction into nothing — `TransactionRow` would still
  /// render "Uncategorized" and the rule would look broken rather than
  /// misaimed.
  func testEverySeededRuleTargetsOneOfTheFourteenSeededCategories() {
    let categoryIDs = Set(DefaultCategorySeed.specs.map(\.id))
    XCTAssertEqual(categoryIDs.count, 14)

    for spec in specs {
      XCTAssertTrue(
        categoryIDs.contains(spec.categoryID),
        "\(spec.pattern) targets a category that is not seeded")
    }
  }

  /// `Category.uncategorizedID` is a *display* sentinel for a nil `categoryID`
  /// and is deliberately never seeded as a row. A rule assigning it would make
  /// "Uncategorized" a category rules can put things in, which is the one thing
  /// the sentinel exists to prevent.
  func testNoSeededRuleTargetsTheUncategorizedSentinel() {
    for spec in specs {
      XCTAssertNotEqual(spec.categoryID, NomiCore.Category.uncategorizedID, spec.pattern)
    }
  }

  // MARK: - Patterns that can actually match

  /// `normalizeDescription` uppercases and strips every digit run, and
  /// `globMatches` is case-sensitive. A lowercase pattern or one containing a
  /// digit is dead on arrival — it compiles, ships, and silently never fires.
  ///
  /// This is not hypothetical: the design's own example list carries
  /// `*UPI/P2M*`, which normalisation turns into `UPI/PM` before any rule sees
  /// it.
  func testNoPatternCanBeDefeatedByNormalisation() {
    for spec in specs {
      XCTAssertEqual(spec.pattern, spec.pattern.uppercased(), "\(spec.pattern) is not uppercase")
      XCTAssertNil(
        spec.pattern.rangeOfCharacter(from: .decimalDigits),
        "\(spec.pattern) contains a digit, which normalizeDescription strips from the value")
    }
  }

  /// The round trip, in one assertion: a pattern is only real if it survives
  /// `normalizeDescription` applied to the *pattern's own* meaningful text.
  func testEveryPatternIsStableUnderTheSameNormalisationTheValueGets() {
    for spec in specs {
      let core = spec.pattern.replacingOccurrences(of: "*", with: "")
      XCTAssertEqual(
        normalizeDescription(core), core,
        "\(spec.pattern) would not survive the normalisation its target string went through")
    }
  }

  // MARK: - Precedence

  func testPrioritiesAreStrictlyAscendingAndAboveTheBase() {
    XCTAssertEqual(specs.map(\.priority), (0..<specs.count).map { DefaultRuleSeed.priorityBase + $0 })
  }

  /// Precedence is ascending priority and evaluation stops at the first match,
  /// so a broad pattern above a narrow one silently eats it. Every merchant name
  /// has to outrank every rail-or-keyword.
  func testEveryMerchantPatternOutranksEveryKeywordPattern() {
    let merchants = Set(DefaultRuleSeed.merchantPatterns.map(\.0))
    let merchantPriorities = specs.filter { merchants.contains($0.pattern) }.map(\.priority)
    let keywordPriorities = specs.filter { !merchants.contains($0.pattern) }.map(\.priority)

    XCTAssertFalse(merchantPriorities.isEmpty)
    XCTAssertFalse(keywordPriorities.isEmpty)
    XCTAssertLessThan(
      merchantPriorities.max() ?? .max, keywordPriorities.min() ?? .min,
      "a keyword above a merchant silently eats it — first match wins")
  }

  /// The specific case that motivated ordering the merchant list by name length
  /// rather than by category: JioMart is groceries and Jio is a phone bill.
  func testTheLongerOfTwoOverlappingMerchantNamesWinsFirst() {
    let jioMart = specs.first { $0.pattern == "*JIOMART*" }
    let jio = specs.first { $0.pattern == "*JIO*" }

    XCTAssertNotNil(jioMart)
    XCTAssertNotNil(jio)
    XCTAssertLessThan(jioMart?.priority ?? .max, jio?.priority ?? .min)
  }

  // MARK: - What it actually categorises

  /// The point of the whole unit, put as a question about behaviour rather than
  /// about the data: run the seed through the real `RuleEngine` against real
  /// narration shapes and check where each one lands.
  ///
  /// The strings are `normalizeDescription`'d first, exactly as
  /// `DraftDerivation` does before a rule ever sees them — which is what makes
  /// `UPI/P2M//SWIGGY` arrive as `UPI/PM//SWIGGY`.
  func testRealNarrationsLandInTheCategoryTheSeedClaims() {
    let cases: [(narration: String, categoryOrdinal: Int)] = [
      ("UPI/P2M/622104477311/SWIGGY/YESB/swiggy@ybl", 1),
      ("UPI-ZOMATO-zomato@paytm-9931204411", 1),
      ("UBER INDIA SYSTEMS", 2),
      ("AIRTEL PREPAID RECHARGE", 3),
      ("ACH-D- HDFC EMI 4471", 5),
      ("ATM CASH WITHDRAWAL KORAMANGALA", 8),
      ("at AMAZON INDIA", 10),
      ("at BLINKIT", 11),
      ("JIOMART GROCERY ORDER", 11),
      ("NEFT/SALARY/ACME TECHNOLOGIES", 13),
    ]

    let rules = specs.map {
      RuleSnapshot(
        id: $0.id, pattern: $0.pattern, categoryID: $0.categoryID, priority: $0.priority,
        isEnabled: true, createdAt: Date(timeIntervalSince1970: 0))
    }

    for (narration, ordinal) in cases {
      let match = RuleEngine.firstMatch(
        normalizedDescription: normalizeDescription(narration), in: rules)
      XCTAssertEqual(
        match?.categoryID, DefaultCategorySeed.seedID(ordinal),
        "\(narration) landed in the wrong category")
    }
  }

  /// The control. Without it, "the seed categorises things" would be satisfied
  /// by a seed containing `*`, which would categorise everything wrongly.
  func testANarrationTheSeedKnowsNothingAboutMatchesNothing() {
    let rules = specs.map {
      RuleSnapshot(
        id: $0.id, pattern: $0.pattern, categoryID: $0.categoryID, priority: $0.priority,
        isEnabled: true, createdAt: Date(timeIntervalSince1970: 0))
    }

    let match = RuleEngine.firstMatch(
      normalizedDescription: normalizeDescription("IMPS/P2A/BHARAT XYZ"), in: rules)
    XCTAssertNil(match, "a narration nothing describes must stay uncategorised")
  }
}
