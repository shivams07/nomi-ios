import Foundation
import Testing

@testable import NomiCore

/// DEC-05 Amendments 1 and 3. The single copy of the match rule, the manual
/// partner rule, the pair states (rule U), the compare-and-set guard (rule C)
/// and the collapse order (A-05 items 16 to 18).
struct TransferRulesTests {
  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar
  }()

  private let savings = UUID()
  private let card = UUID()
  private let debit = Direction.debit.rawValue
  private let credit = Direction.credit.rawValue

  // Fixed vectors, as Amendment 3 names them.
  private let g1 = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
  private let g2 = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
  private let g3 = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

  private func pair(_ groupID: UUID?, _ sourceRaw: String?) -> TransferPair {
    TransferPair(groupID: groupID, sourceRaw: sourceRaw)
  }

  /// The six shapes this build never writes (U6).
  private var unrecognized: [TransferPair] {
    [
      pair(nil, "zzz"),
      pair(g1, "zzz"),
      pair(g1, nil),
      pair(g1, "rejected"),
      pair(nil, "auto"),
      pair(nil, "manual"),
    ]
  }

  /// 10 November 2026, 12:00 IST, plus whole days.
  private func day(_ offset: Int) -> Date {
    var components = DateComponents()
    components.year = 2026
    components.month = 11
    components.day = 10
    components.hour = 12
    return calendar.date(byAdding: .day, value: offset, to: calendar.date(from: components)!)!
  }

  private func leg(
    id: UUID = UUID(),
    offset: Int = 0,
    amountMinor: Int = 2_000_000,
    currency: String = "INR",
    direction: String? = nil,
    account: UUID?,
    group: UUID? = nil,
    source: String? = nil
  ) -> TransferLeg {
    TransferLeg(
      id: id,
      date: day(offset),
      amountMinor: amountMinor,
      currencyCode: currency,
      directionRaw: direction ?? debit,
      accountID: account,
      transferGroupID: group,
      transferSourceRaw: source
    )
  }

  /// A leg whose transfer pair is `p`, on `account`.
  private func leg(with p: TransferPair, account: UUID, offset: Int = 0, direction: String? = nil) -> TransferLeg {
    leg(offset: offset, direction: direction, account: account, group: p.groupID, source: p.sourceRaw)
  }

  /// Fixture F's two legs: savings debit 10 Nov, card credit 11 Nov, 20,000.00.
  private func fixtureF() -> (debit: TransferLeg, credit: TransferLeg) {
    let s = leg(offset: 0, direction: debit, account: savings)
    let c = leg(offset: 1, direction: credit, account: card)
    return (s, c)
  }

  // MARK: - matches

  @Test func fixtureFLegsMatch() {
    let (s, c) = fixtureF()
    #expect(TransferRules.matches(s, c, calendar: calendar))
  }

  @Test func aUSDLegNeverMatches() {
    let (s, _) = fixtureF()
    let usd = leg(offset: 1, currency: "USD", direction: credit, account: card)
    #expect(!TransferRules.matches(s, usd, calendar: calendar))
  }

  @Test func twoDebitsNeverMatch() {
    let (s, _) = fixtureF()
    let other = leg(offset: 1, direction: debit, account: card)
    #expect(!TransferRules.matches(s, other, calendar: calendar))
  }

  @Test func anAmountOnePaiseOffNeverMatches() {
    let (s, _) = fixtureF()
    let off = leg(offset: 1, amountMinor: 2_000_001, direction: credit, account: card)
    #expect(!TransferRules.matches(s, off, calendar: calendar))
  }

  @Test func theSameAccountNeverMatches() {
    let (s, _) = fixtureF()
    let same = leg(offset: 1, direction: credit, account: savings)
    #expect(!TransferRules.matches(s, same, calendar: calendar))
  }

  @Test func aLegWithNoAccountNeverMatches() {
    let (s, _) = fixtureF()
    let unassigned = leg(offset: 1, direction: credit, account: nil)
    #expect(!TransferRules.matches(s, unassigned, calendar: calendar))
    #expect(!TransferRules.matches(unassigned, s, calendar: calendar))
  }

  @Test func fourDaysApartNeverMatchesAndThreeDaysApartDoes() {
    let (s, _) = fixtureF()
    let three = leg(offset: 3, direction: credit, account: card)
    let four = leg(offset: 4, direction: credit, account: card)
    #expect(TransferRules.matches(s, three, calendar: calendar))
    #expect(!TransferRules.matches(s, four, calendar: calendar))
  }

  @Test func theWindowIsTheAbsoluteDayDifferenceInEitherDirection() {
    let (s, _) = fixtureF()
    let earlierCredit = leg(offset: -3, direction: credit, account: card)
    #expect(TransferRules.matches(s, earlierCredit, calendar: calendar))
  }

  @Test func aRowNeverMatchesItself() {
    let (s, _) = fixtureF()
    #expect(!TransferRules.matches(s, s, calendar: calendar))
  }

  // MARK: - states and free (Amendment 3, U4)

  @Test func stateClassifiesEveryPair() {
    #expect(TransferRules.state(pair(nil, nil)) == .unmarked)
    #expect(TransferRules.state(pair(g1, "auto")) == .auto)
    #expect(TransferRules.state(pair(g1, "manual")) == .manual)
    #expect(TransferRules.state(pair(nil, "rejected")) == .rejected)
    for shape in unrecognized {
      #expect(TransferRules.state(shape) == .unrecognized, "\(shape)")
    }
  }

  @Test func onlyAnUnmarkedLegIsFree() {
    #expect(TransferRules.isFree(leg(with: pair(nil, nil), account: card)))
    #expect(!TransferRules.isFree(leg(with: pair(g1, "auto"), account: card)))
    #expect(!TransferRules.isFree(leg(with: pair(g1, "manual"), account: card)))
    #expect(!TransferRules.isFree(leg(with: pair(nil, "rejected"), account: card)))
    for shape in unrecognized {
      #expect(!TransferRules.isFree(leg(with: shape, account: card)), "\(shape)")
    }
  }

  @Test func eligibleIsMatchWithBothLegsFree() {
    let (s, c) = fixtureF()
    #expect(TransferRules.isEligiblePair(s, c, calendar: calendar))
    let rejectedCredit = leg(offset: 1, direction: credit, account: card, group: nil, source: "rejected")
    #expect(!TransferRules.isEligiblePair(s, rejectedCredit, calendar: calendar))
  }

  // MARK: - manualPartner (A-05 item 6, item 18)

  @Test func aSingleFreeMatchIsTheManualPartner() {
    let (s, c) = fixtureF()
    #expect(TransferRules.manualPartner(for: s, among: [c], calendar: calendar) == c.id)
  }

  @Test func twoCandidatesMeanNoPartner() {
    let s1 = leg(offset: 0, amountMinor: 500_000, direction: debit, account: savings)
    let c1 = leg(offset: 1, amountMinor: 500_000, direction: credit, account: card)
    let c2 = leg(offset: 2, amountMinor: 500_000, direction: credit, account: card)
    #expect(TransferRules.manualPartner(for: s1, among: [c1, c2], calendar: calendar) == nil)
    #expect(TransferRules.manualPartner(for: s1, among: [c1], calendar: calendar) == c1.id)
  }

  @Test func aRejectedOrGroupedOnlyCandidateGivesNoPartner() {
    let (s, _) = fixtureF()
    let rejected = leg(offset: 1, direction: credit, account: card, group: nil, source: "rejected")
    let grouped = leg(offset: 1, direction: credit, account: card, group: g1, source: "auto")
    #expect(TransferRules.manualPartner(for: s, among: [rejected], calendar: calendar) == nil)
    #expect(TransferRules.manualPartner(for: s, among: [grouped], calendar: calendar) == nil)
  }

  @Test func anUnrecognizedOnlyCandidateGivesNoPartner() {
    let (s, _) = fixtureF()
    let zzz = leg(offset: 1, direction: credit, account: card, group: nil, source: "zzz")
    let zzzWithGroup = leg(offset: 1, direction: credit, account: card, group: g1, source: "zzz")
    #expect(TransferRules.manualPartner(for: s, among: [zzz], calendar: calendar) == nil)
    #expect(TransferRules.manualPartner(for: s, among: [zzzWithGroup], calendar: calendar) == nil)
  }

  @Test func aRejectedRowCanStillBeMarkedAndFindsItsPartner() {
    let c = leg(offset: 1, direction: credit, account: card)
    let rejectedRow = leg(offset: 0, direction: debit, account: savings, group: nil, source: "rejected")
    #expect(TransferRules.manualPartner(for: rejectedRow, among: [c], calendar: calendar) == c.id)
  }

  // MARK: - pipelineMayWrite (Amendment 3, rule C and the state table)

  @Test func pipelineWriteMatrix() {
    let currents: [TransferPair] = [pair(nil, nil), pair(g1, "auto"), pair(g1, "manual"), pair(nil, "rejected")] + unrecognized
    let incomings: [TransferPair] = [pair(nil, nil), pair(g2, "auto"), pair(g2, "manual"), pair(nil, "rejected"), pair(g2, "zzz")]
    let frozen: [Bool] = [false, false, false, false, false]
    let expected: [[Bool]] = [
      [true, true, true, true, false],
      [false, true, true, true, false],
      frozen,
      frozen,
    ] + Array(repeating: frozen, count: unrecognized.count)
    for (i, current) in currents.enumerated() {
      for (j, incoming) in incomings.enumerated() {
        #expect(
          TransferRules.pipelineMayWrite(read: current, current: current, incoming: incoming) == expected[i][j],
          "current \(current) incoming \(incoming)")
      }
    }
  }

  @Test func pipelineWriteRequiresTheReadPairToMatch() {
    // (a) no read pair: nothing is written.
    #expect(!TransferRules.pipelineMayWrite(read: nil, current: pair(nil, nil), incoming: pair(g2, "auto")))
    // (b) the row was marked after the read: the stale unmarked read is refused.
    #expect(!TransferRules.pipelineMayWrite(read: pair(nil, nil), current: pair(g1, "manual"), incoming: pair(nil, nil)))
    // (c) the cleared-partner race: read manual, now unmarked, stale re-mark refused.
    #expect(!TransferRules.pipelineMayWrite(read: pair(g1, "manual"), current: pair(nil, nil), incoming: pair(g1, "manual")))
    // (d) read and current agree and unmarked: the one true case.
    #expect(TransferRules.pipelineMayWrite(read: pair(nil, nil), current: pair(nil, nil), incoming: pair(g2, "manual")))
  }

  // MARK: - collapsedTransferFields (A-05 item 17, item 18)

  @Test func aManualOrRejectedSurvivorKeepsItsOwnPair() {
    let kept = TransferRules.collapsedTransferFields(
      survivor: pair(g1, "manual"), others: [pair(g2, "auto"), pair(nil, "rejected")])
    #expect(kept == pair(g1, "manual"))
    let rejected = TransferRules.collapsedTransferFields(
      survivor: pair(nil, "rejected"), others: [pair(g2, "manual")])
    #expect(rejected == pair(nil, "rejected"))
  }

  @Test func anyOtherRejectedWinsOverAManualOrAuto() {
    let result = TransferRules.collapsedTransferFields(
      survivor: pair(nil, nil), others: [pair(g1, "manual"), pair(nil, "rejected")])
    #expect(result == pair(nil, "rejected"))
    let overAuto = TransferRules.collapsedTransferFields(
      survivor: pair(g2, "auto"), others: [pair(nil, "rejected")])
    #expect(overAuto == pair(nil, "rejected"))
  }

  @Test func otherManualBeatsASurvivorAuto() {
    let result = TransferRules.collapsedTransferFields(
      survivor: pair(g2, "auto"), others: [pair(nil, nil), pair(g1, "manual")])
    #expect(result == pair(g1, "manual"))
  }

  @Test func survivorAutoBeatsAnOtherAuto() {
    let result = TransferRules.collapsedTransferFields(
      survivor: pair(g2, "auto"), others: [pair(g1, "auto")])
    #expect(result == pair(g2, "auto"))
  }

  @Test func anOtherAutoIsTakenWhenTheSurvivorHasNone() {
    let result = TransferRules.collapsedTransferFields(
      survivor: pair(nil, nil), others: [pair(nil, nil), pair(g1, "auto")])
    #expect(result == pair(g1, "auto"))
  }

  @Test func noTransferStateAnywhereStaysNone() {
    let result = TransferRules.collapsedTransferFields(survivor: pair(nil, nil), others: [pair(nil, nil)])
    #expect(result == pair(nil, nil))
  }

  /// Amendment 3, rule U3. An unrecognised pair anywhere in the group stops the
  /// collapse. Lim's vector and its mirror are both here.
  @Test func anUnrecognizedPairAnywhereStopsTheCollapse() {
    #expect(TransferRules.collapsedTransferFields(survivor: pair(nil, "zzz"), others: [pair(g1, "manual")]) == nil)
    #expect(TransferRules.collapsedTransferFields(survivor: pair(nil, nil), others: [pair(g1, "zzz")]) == nil)
    #expect(TransferRules.collapsedTransferFields(
      survivor: pair(g1, "manual"), others: [pair(nil, nil), pair(g2, nil)]) == nil)
    #expect(TransferRules.collapsedTransferFields(survivor: pair(g1, nil), others: [pair(nil, nil)]) == nil)
  }

  /// Amendment 3 (A-05 item 17, corrected claim). For every recognised survivor
  /// and every sequence of one or two recognised others, the collapse result is
  /// recognised and either unchanged or writable on the survivor. 4 survivors ×
  /// (4 + 16) sequences = 80 cases.
  @Test func everyCollapseResultIsWritableOnTheSurvivor() throws {
    let recognised = [pair(nil, nil), pair(g2, "auto"), pair(g3, "manual"), pair(nil, "rejected")]
    let survivors = [pair(nil, nil), pair(g1, "auto"), pair(g1, "manual"), pair(nil, "rejected")]
    var others: [[TransferPair]] = recognised.map { [$0] }
    for first in recognised {
      for second in recognised {
        others.append([first, second])
      }
    }
    #expect(others.count == 20)

    var checked = 0
    for survivor in survivors {
      for group in others {
        let result = try #require(TransferRules.collapsedTransferFields(survivor: survivor, others: group))
        #expect(TransferRules.state(result) != .unrecognized)
        #expect(
          result == survivor
            || TransferRules.pipelineMayWrite(read: survivor, current: survivor, incoming: result),
          "survivor \(survivor) others \(group) gave \(result)")
        checked += 1
      }
    }
    #expect(checked == 80)
  }
}
