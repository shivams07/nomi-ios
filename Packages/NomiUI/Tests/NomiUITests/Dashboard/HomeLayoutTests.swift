import Foundation
import NomiCore
import Testing
@testable import NomiUI

// clt-harness: include

/// HM1's pure rules: which Home layout the sheet draws, and which periods the
/// period menu offers. Swift-testing, so the CLT harness runs them (V2).
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

  // MARK: - Mode matrix

  /// Five mail states (connected with and without a last sync, connecting,
  /// disconnected, failed) times "has any transaction". Ten cases.
  @Test func modeMatrixOfMailStateAndTransactions() {
    let cases: [(name: String, mail: MailConnectionState, hasAny: Bool, expected: HomeLayout.Mode)] = [
      ("connected, never synced, no rows", .connected(address: "a@example.in", lastSync: nil), false, .normal(showAttention: false)),
      ("connected, never synced, rows", .connected(address: "a@example.in", lastSync: nil), true, .normal(showAttention: false)),
      ("connected, synced, no rows", .connected(address: "a@example.in", lastSync: Self.now), false, .normal(showAttention: false)),
      ("connected, synced, rows", .connected(address: "a@example.in", lastSync: Self.now), true, .normal(showAttention: false)),
      ("connecting, no rows", .connecting, false, .normal(showAttention: false)),
      ("connecting, rows", .connecting, true, .normal(showAttention: false)),
      ("disconnected, no rows", .disconnected, false, .firstRun),
      ("disconnected, rows", .disconnected, true, .normal(showAttention: true)),
      ("failed, no rows", .failed(.connectionFailed), false, .firstRun),
      ("failed, rows", .failed(.connectionFailed), true, .normal(showAttention: true)),
    ]
    for item in cases {
      #expect(
        HomeLayout.mode(mail: item.mail, hasAnyTransaction: item.hasAny) == item.expected,
        "\(item.name)"
      )
    }
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
