import Foundation
import NomiCore
import SwiftData

/// One seeded rule, as a value.
///
/// Deliberately not a `@Model`, for the same reason `CategorySeedSpec` is not:
/// the *content* of the seed — the patterns, the ids, which category each one
/// targets — is the part that can be wrong, and it has to live on this side of
/// the `@Model` line or nothing about it is ever executed by a test.
public struct RuleSeedSpec: Sendable, Equatable, Identifiable {
  public let id: UUID
  /// A glob against `Transaction.normalizedDescription`. See
  /// `DefaultRuleSeed`'s note on why every one of these is uppercase and
  /// digit-free.
  public let pattern: String
  public let categoryID: UUID
  public let priority: Int

  public init(id: UUID, pattern: String, categoryID: UUID, priority: Int) {
    self.id = id
    self.pattern = pattern
    self.categoryID = categoryID
    self.priority = priority
  }
}

/// A starter rule set, so a fresh install categorises something.
///
/// `DefaultCategorySeed` seeds fourteen categories and nothing seeds a `Rule`,
/// so `RuleEngine.apply` returns `nil` for every row forever: `categoryID` stays
/// nil, every row reads "Uncategorized", and every filter chip except
/// "Uncategorized" is empty. The learning half of the loop was specified and the
/// bootstrap half was not.
///
/// **The ids are fixed constants, and that is load-bearing** — the same
/// argument `DefaultCategorySeed` makes. `Rule` is a SwiftData model on a
/// CloudKit-backed store, so two devices signed into one iCloud account each run
/// this seed on their own first launch. Generated ids would give the user two of
/// every rule the moment those devices synced, and there is no reconcile pass
/// for rules. Matching on `pattern` instead would break the moment anyone edits
/// one.
///
/// ## Why every pattern is uppercase and contains no digits
///
/// `globMatches` is case-sensitive, and it is matched against
/// `normalizedDescription`, which `normalizeDescription` produces by
/// uppercasing, **stripping every digit run**, and collapsing whitespace. A
/// lowercase pattern can never match; neither can one containing a digit.
///
/// That second rule bites in a way worth naming: the UPI transaction-type codes
/// are `P2M` and `P2A`, and by the time a rule sees them they are `PM` and `PA`.
/// A seeded `*UPI/P2M*` would be dead on arrival. `RulePrecedenceTests` already
/// matches against `"UPI/PM//SWIGGY/HDFC"`, which is what the real string looks
/// like after normalisation.
///
/// ## Two tiers, and the order is the point
///
/// Precedence is ascending `priority`, first match wins, evaluation stops. So a
/// broad pattern placed above a narrow one silently eats it: `*UPI/PA*` sitting
/// above `*AMAZON*` would file an Amazon payment as a P2P transfer. Every
/// merchant-name pattern therefore sorts before every rail-or-keyword pattern,
/// and `specs` is built in that order rather than category by category.
///
/// ## Two patterns the design's examples list that are deliberately absent
///
/// - **`*UPI/P2M*`** (as `*UPI/PM*`) under UPI & Food Delivery. It matches every
///   merchant UPI payment there is — groceries, shopping, medicine — and would
///   file the majority of a user's spend under food delivery. A wrong category
///   the user must undo is worse than an empty one they can fill.
/// - **`*NEFT*`** under Salary & Income. NEFT is a rail, not a purpose: rent,
///   fee payments and transfers all ride it, and rules do not see direction, so
///   this would book outgoing money as income. `*SALARY*` catches the actual
///   salary credit — `NEFT/SALARY/ACME TECHNOLOGIES` in the SBI fixture — with
///   none of that.
///
/// Both are data, so either can be added back with a one-line edit if Shivam
/// wants the recall over the precision.
public enum DefaultRuleSeed {

  /// `00000000-0000-0000-0000-0000000020NN`. The same obviously-synthetic shape
  /// `DefaultCategorySeed.seedID` uses, on a different block so the two can
  /// never collide.
  static func seedID(_ ordinal: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-0000000020%02d", ordinal))!
  }

  /// Seeded rules sit far above anything a hand-ordered rule list produces —
  /// `reorder` writes priorities as array indices, so a user's list occupies
  /// 0..<n.
  ///
  /// **This does not yet achieve what it is for.** `SwiftDataRuleStore.create`
  /// gives a new rule `(every existing priority).max() + 1`, which with these
  /// present is `priorityBase + specs.count`, so a user's first rule lands
  /// *below* the whole seed and loses to it. No value here fixes that — it is computed
  /// relative to whatever the seed is, and `Int.max` would make `max + 1`
  /// overflow. The fix is one line in `create`, in a file this unit does not
  /// own; escalated with the PR.
  public static let priorityBase = 1_000_000

  /// Merchant names. Narrow, unambiguous, and first.
  ///
  /// Grouped by category *except* where one merchant's name contains another's:
  /// `JIOMART` is groceries and `JIO` is a phone bill, and since precedence is
  /// position in this list, the longer one has to come first or every JioMart
  /// order is filed as a recharge.
  ///
  /// `*OLACABS*` rather than `*OLA*` for the same class of reason from the other
  /// direction: `OLA` is a substring of `SOLAR` and `COLA`, and a solar bill
  /// filed as a taxi is the sort of wrong that makes someone stop trusting the
  /// ledger. Ola's own narrations carry `OLACABS` or `OLAMONEY`.
  static let merchantPatterns: [(String, Int)] = [
    // UPI & Food Delivery
    ("*SWIGGY*", 1), ("*ZOMATO*", 1), ("*DOMINOS*", 1), ("*EATCLUB*", 1),
    // Ride-hailing
    ("*UBER*", 2), ("*OLACABS*", 2), ("*OLAMONEY*", 2), ("*RAPIDO*", 2), ("*BLUSMART*", 2),
    // Groceries, out of category order: see the note above.
    ("*JIOMART*", 11),
    // Recharge & Utilities
    ("*AIRTEL*", 3), ("*JIO*", 3), ("*VODAFONE*", 3), ("*BESCOM*", 3), ("*TATAPOWER*", 3),
    // SIP & Investments
    ("*ZERODHA*", 6), ("*GROWW*", 6), ("*UPSTOX*", 6), ("*KUVERA*", 6),
    // Insurance
    ("*POLICYBAZAAR*", 7), ("*LIC OF INDIA*", 7),
    // Shopping
    ("*AMAZON*", 10), ("*FLIPKART*", 10), ("*MYNTRA*", 10), ("*AJIO*", 10), ("*NYKAA*", 10),
    // Groceries
    ("*BLINKIT*", 11), ("*ZEPTO*", 11), ("*BIGBASKET*", 11), ("*DMART*", 11),
    ("*INSTAMART*", 11),
    // Health
    ("*PHARMEASY*", 12), ("*NETMEDS*", 12), ("*APOLLO*", 12),
  ]

  /// Rails and keywords. Broader, so they sort after every merchant above.
  ///
  /// These are globs with no word-boundary syntax available, so each one has a
  /// known false positive and each is kept on the same judgement: the thing it
  /// catches is commoner in Indian retail narrations than the thing it catches
  /// by accident.
  ///
  /// - `*RENT*` also matches `CURRENT` and `PARENT`.
  /// - `*EMI*` also matches `CHEMIST` and `PREMIER`.
  /// - `*SIP*` also matches `GOSSIP`.
  /// - `*ATM*` also matches `ATMOSPHERE`.
  ///
  /// All four are data. Any of them can be narrowed or dropped without a code
  /// change once real narrations say which way the trade actually goes.
  static let keywordPatterns: [(String, Int)] = [
    ("*RECHARGE*", 3),
    ("*RENT*", 4),
    ("*EMI*", 5), ("*LOAN*", 5),
    ("*MUTUAL FUND*", 6), ("*SIP*", 6),
    ("*INSURANCE*", 7),
    ("*ATM*", 8), ("*CASH WITHDRAWAL*", 8),
    ("*UPI/PA*", 9),
    ("*PHARMACY*", 12), ("*HOSPITAL*", 12),
    ("*SALARY*", 13),
  ]

  /// Merchants first, then keywords, priorities ascending in that order.
  ///
  /// The second element of each pair is the ordinal of the category in
  /// `DefaultCategorySeed` — 1-based, the same ordinal `seedID` takes — so the
  /// two seeds cannot drift apart by anything less than an edit to both.
  public static let specs: [RuleSeedSpec] = (merchantPatterns + keywordPatterns)
    .enumerated()
    .map { index, entry in
      RuleSeedSpec(
        id: seedID(index + 1),
        pattern: entry.0,
        categoryID: DefaultCategorySeed.seedID(entry.1),
        priority: priorityBase + index
      )
    }

  /// The specs not already present, given the ids the store already holds.
  ///
  /// Pure, and separated from the insert for the same reason
  /// `DefaultCategorySeed.missing` is: this is the part that decides, and it is
  /// the part a test can run.
  public static func missing(existingIDs: Set<UUID>) -> [RuleSeedSpec] {
    specs.filter { !existingIDs.contains($0.id) }
  }
}

// MARK: - Applying the seed
//
// Below this line touches `@Model`. Keep it thin: everything that decides
// anything is above.

extension DefaultRuleSeed {
  /// Inserts whatever is missing. Safe to call on every launch, and it is called
  /// on every launch — idempotent by id, exactly like the category seed.
  ///
  /// It does **not** rewrite existing rows, and that matters more here than it
  /// does for categories: a user who edited a seeded rule's pattern, retargeted
  /// it at another category, disabled it, or dragged it up their list keeps all
  /// of that. Re-seeding over them would undo the user's own work on every
  /// launch.
  ///
  /// A rule the user *deleted* comes back, because a deleted id is
  /// indistinguishable from one that was never seeded. Tracking deletions would
  /// need a tombstone this schema does not have; noted rather than hidden.
  @MainActor
  static func apply(in context: ModelContext) throws {
    let existing = try context.fetch(FetchDescriptor<Rule>())
    let existingIDs = Set(existing.map(\.id))

    for spec in missing(existingIDs: existingIDs) {
      context.insert(
        Rule(
          id: spec.id,
          pattern: spec.pattern,
          categoryID: spec.categoryID,
          priority: spec.priority
        )
      )
    }

    if context.hasChanges {
      try context.save()
    }
  }
}
