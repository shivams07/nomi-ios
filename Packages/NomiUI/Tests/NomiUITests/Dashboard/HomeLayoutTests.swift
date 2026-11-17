import Foundation
import NomiCore
import Testing
@testable import NomiUI

// clt-harness: include

/// HM1's pure rules: which Home layout the sheet draws, and which periods the
/// period menu offers. Swift-testing, so the CLT harness runs them (V2). S1b adds
/// the order of the sheet and the Review card's counts.
@Suite("Home layout")
struct HomeLayoutTests {
  private static let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }()

  /// 8 November 2026, UTC.
  private static let now: Date = {
    var components = DateComponents()
    components.year = 2026
    components.month = 11
    components.day = 8
    components.hour = 12
    return utc.date(from: components)!
  }()

  private static let neverConnected = MailConnectionHistory.never
  private static let connectedBefore = MailConnectionHistory(hasEverConnected: true, lastSync: nil)

  // MARK: - Mode matrix

  /// Five mail states (connected with and without a last sync, connecting,
  /// disconnected, failed) times "has any transaction", for a user who has
  /// connected before, and for one who never has.
  @Test func modeMatrixOfMailStateAndTransactions() {
    let cases: [(name: String, mail: MailConnectionState, history: MailConnectionHistory, hasAny: Bool, expected: HomeLayout.Mode)] = [
      ("connected, never synced, no rows", .connected(address: "a@example.in", lastSync: nil), Self.neverConnected, false, .normal(showAttention: false)),
      ("connected, never synced, rows", .connected(address: "a@example.in", lastSync: nil), Self.neverConnected, true, .normal(showAttention: false)),
      ("connected, synced, no rows", .connected(address: "a@example.in", lastSync: Self.now), Self.connectedBefore, false, .normal(showAttention: false)),
      ("connected, synced, rows", .connected(address: "a@example.in", lastSync: Self.now), Self.connectedBefore, true, .normal(showAttention: false)),
      ("connecting, no rows", .connecting, Self.neverConnected, false, .normal(showAttention: false)),
      ("connecting, rows", .connecting, Self.connectedBefore, true, .normal(showAttention: false)),
      ("disconnected, never connected, no rows", .disconnected, Self.neverConnected, false, .firstRun),
      ("disconnected, never connected, rows", .disconnected, Self.neverConnected, true, .normal(showAttention: false)),
      ("disconnected after connecting, no rows", .disconnected, Self.connectedBefore, false, .firstRun),
      ("disconnected after connecting, rows", .disconnected, Self.connectedBefore, true, .normal(showAttention: true)),
      ("failed, no rows", .failed(.connectionFailed), Self.connectedBefore, false, .firstRun),
      ("failed, rows", .failed(.connectionFailed), Self.connectedBefore, true, .normal(showAttention: true)),
    ]
    for item in cases {
      #expect(
        HomeLayout.mode(mail: item.mail, history: item.history, hasAnyTransaction: item.hasAny) == item.expected,
        "\(item.name)"
      )
    }
  }

  // MARK: - Sheet order (S1b step 1)

  /// Without attention the sheet runs budget, review, grid, upcoming, recent, then the
  /// mail status line.
  @Test func sheetOrderWithoutAttention() {
    #expect(HomeLayout.sections(showAttention: false) == [
      .leftToSpend, .review, .whereItWent, .comingUp, .recent, .mailStatus,
    ])
  }

  /// With attention the attention row leads, and the rest keeps its order.
  @Test func sheetOrderWithAttentionPutsTheRowFirst() {
    #expect(HomeLayout.sections(showAttention: true) == [
      .attention, .leftToSpend, .review, .whereItWent, .comingUp, .recent, .mailStatus,
    ])
  }

  // MARK: - Period menu anchors

  @Test func recentAnchorsMonthIs12() {
    let anchors = DashboardPeriod.recentAnchors(basis: .calendarMonth, now: Self.now, calendar: Self.utc)
    #expect(anchors.count == 12)
    #expect(Set(anchors.map { DashboardPeriod.period(basis: .calendarMonth, anchor: $0, calendar: Self.utc) }).count == 12)
  }

  @Test func recentAnchorsFYIs3() {
    let anchors = DashboardPeriod.recentAnchors(basis: .financialYear, now: Self.now, calendar: Self.utc)
    #expect(anchors.count == 3)
  }

  /// The first anchor is the current period on each basis, then the menu runs
  /// back in time. The oldest month is twelve periods before now.
  @Test func recentAnchorsStartAtCurrent() {
    let months = DashboardPeriod.recentAnchors(basis: .calendarMonth, now: Self.now, calendar: Self.utc)
    let periods = months.map { DashboardPeriod.period(basis: .calendarMonth, anchor: $0, calendar: Self.utc) }
    #expect(periods.first == .month(year: 2026, month: 11))
    #expect(periods.last == .month(year: 2025, month: 12))

    let years = DashboardPeriod.recentAnchors(basis: .financialYear, now: Self.now, calendar: Self.utc)
    let fys = years.map { DashboardPeriod.period(basis: .financialYear, anchor: $0, calendar: Self.utc) }
    #expect(fys == [.financialYear(startingYear: 2026), .financialYear(startingYear: 2025), .financialYear(startingYear: 2024)])
  }
}

/// S1b step 3. The Review card's counts come from `ReviewQueueLogic.items`, the same
/// list the queue shows, so the card and the queue cannot disagree.
@Suite("Review card counts")
struct ReviewCountsTests {
  private let calendar = NomiCalendar.india

  /// 16 Nov 2026, the day every fixture is written against.
  private var now: Date {
    calendar.date(from: DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 11, day: 16, hour: 12))!
  }

  private func row(
    _ name: String,
    categoryID: UUID? = nil,
    needsReview: Bool = false,
    isTransfer: Bool = false
  ) -> NomiCore.Transaction {
    NomiCore.Transaction(
      date: now,
      descriptionText: name,
      merchantName: name,
      normalizedDescription: normalizeDescription(name),
      amountMinor: 115_000,
      categoryID: categoryID,
      categorySourceRaw: categoryID == nil ? CategorySource.none.rawValue : CategorySource.manual.rawValue,
      accountID: UUID(),
      sourceRaw: IngestSource.email.rawValue,
      mergedCount: 1,
      needsReview: needsReview,
      needsReviewReasonRaw: nil,
      transferGroupID: isTransfer ? UUID() : nil,
      transferSourceRaw: isTransfer ? TransferSource.auto.rawValue : nil
    )
  }

  /// Total is the queue's length. Uncategorised counts this month's rows with no
  /// category (transfers excluded). Unsure counts flagged rows that already have a
  /// category, so a row in both places is counted once, as uncategorised.
  @Test func countsSplitTheQueueIntoUncategorisedAndUnsure() {
    let flaggedUnsure = row("Heuristic", categoryID: UUID(), needsReview: true)
    let flaggedUncategorised = row("Unknown", needsReview: true)
    let monthUncategorised = row("Cash")
    let monthTransfer = row("Move", isTransfer: true)
    let monthCategorised = row("Fuel", categoryID: UUID())

    let counts = ReviewCounts(
      items: ReviewQueueLogic.items(
        flagged: [flaggedUnsure, flaggedUncategorised],
        monthRows: [monthUncategorised, monthTransfer, monthCategorised],
        now: now,
        calendar: calendar
      )
    )

    #expect(counts.total == 3)
    #expect(counts.uncategorised == 2)
    #expect(counts.unsure == 1)
  }

  @Test func emptyQueueHasNoCounts() {
    let counts = ReviewCounts(items: [])
    #expect(counts.total == 0)
    #expect(counts.uncategorised == 0)
    #expect(counts.unsure == 0)
  }
}
