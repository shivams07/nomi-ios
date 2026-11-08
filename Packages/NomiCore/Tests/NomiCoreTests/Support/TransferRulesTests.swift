import Foundation
import Testing

@testable import NomiCore

/// DEC-05 Amendment 1. The single copy of the match rule, the manual-partner
/// rule, the pipeline write guard (A-05 item 16) and the collapse order (item 17).
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

  @Test func anAmountOneRupeeOrPaiseOffNeverMatches() {
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

  // MARK: - free, eligible

  @Test func rejectedAndGroupedRowsAreNotFree() {
    #expect(TransferRules.isFree(leg(account: card)))
    #expect(!TransferRules.isFree(leg(account: card, source: "rejected")))
    #expect(!TransferRules.isFree(leg(account: card, group: UUID(), source: "auto")))
    #expect(!TransferRules.isFree(leg(account: card, group: UUID(), source: "manual")))
  }

  @Test func eligibleIsMatchWithBothLegsFree() {
    let (s, c) = fixtureF()
    #expect(TransferRules.isEligiblePair(s, c, calendar: calendar))
    let rejectedCredit = leg(offset: 1, direction: credit, account: card, source: "rejected")
    #expect(!TransferRules.isEligiblePair(s, rejectedCredit, calendar: calendar))
  }

  // MARK: - manualPartner (A-05 item 6)

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
    let rejected = leg(offset: 1, direction: credit, account: card, source: "rejected")
    let grouped = leg(offset: 1, direction: credit, account: card, group: UUID(), source: "auto")
    #expect(TransferRules.manualPartner(for: s, among: [rejected], calendar: calendar) == nil)
    #expect(TransferRules.manualPartner(for: s, among: [grouped], calendar: calendar) == nil)
  }

  @Test func aRejectedRowCanStillBeMarkedAndFindsItsPartner() {
    let c = leg(offset: 1, direction: credit, account: card)
    let rejectedRow = leg(offset: 0, direction: debit, account: savings, source: "rejected")
    #expect(TransferRules.manualPartner(for: rejectedRow, among: [c], calendar: calendar) == c.id)
  }

  // MARK: - pipelineMayWrite (A-05 item 16)

  @Test func pipelineWriteMatrix() {
    let currents: [String?] = [nil, "auto", "manual", "rejected", "zzz"]
    let incomings: [String?] = [nil, "auto", "manual", "rejected"]
    let expected: [[Bool]] = [
      // nil current: always
      [true, true, true, true],
      // auto current: only to auto, manual, rejected
      [false, true, true, true],
      // manual current: never
      [false, false, false, false],
      // rejected current: never
      [false, false, false, false],
      // unknown current: never
      [false, false, false, false],
    ]
    for (i, current) in currents.enumerated() {
      for (j, incoming) in incomings.enumerated() {
        #expect(
          TransferRules.pipelineMayWrite(currentRaw: current, incomingRaw: incoming) == expected[i][j],
          "current \(String(describing: current)) incoming \(String(describing: incoming))")
      }
    }
  }

  // MARK: - collapsedTransferFields (A-05 item 17), one test per rule

  private let g1 = UUID()
  private let g2 = UUID()

  @Test func aManualOrRejectedSurvivorKeepsItsOwnPair() {
    let kept = TransferRules.collapsedTransferFields(
      survivor: (g1, "manual"), others: [(g2, "auto"), (nil, "rejected")])
    #expect(kept == (g1, "manual"))
    let rejected = TransferRules.collapsedTransferFields(
      survivor: (nil, "rejected"), others: [(g2, "manual")])
    #expect(rejected == (nil, "rejected"))
  }

  @Test func anyOtherRejectedWinsOverAManualOrAuto() {
    let result = TransferRules.collapsedTransferFields(
      survivor: (nil, nil), others: [(g1, "manual"), (nil, "rejected")])
    #expect(result == (nil, "rejected"))
    let overAuto = TransferRules.collapsedTransferFields(
      survivor: (g2, "auto"), others: [(nil, "rejected")])
    #expect(overAuto == (nil, "rejected"))
  }

  @Test func otherManualBeatsASurvivorAuto() {
    let result = TransferRules.collapsedTransferFields(
      survivor: (g2, "auto"), others: [(nil, nil), (g1, "manual")])
    #expect(result == (g1, "manual"))
  }

  @Test func survivorAutoBeatsAnOtherAuto() {
    let result = TransferRules.collapsedTransferFields(
      survivor: (g2, "auto"), others: [(g1, "auto")])
    #expect(result == (g2, "auto"))
  }

  @Test func anOtherAutoIsTakenWhenTheSurvivorHasNone() {
    let result = TransferRules.collapsedTransferFields(
      survivor: (nil, nil), others: [(nil, nil), (g1, "auto")])
    #expect(result == (g1, "auto"))
  }

  @Test func noTransferStateAnywhereStaysNone() {
    let result = TransferRules.collapsedTransferFields(survivor: (nil, nil), others: [(nil, nil)])
    #expect(result == (nil, nil))
  }
}
