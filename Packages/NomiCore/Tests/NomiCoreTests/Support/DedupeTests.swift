import Foundation
import Testing
@testable import NomiCore

struct DedupeTests {
  @Test func dedupeKeyIsStableForIdenticalInput() {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let key1 = makeDedupeKey(date: date, amountMinor: 4500, directionRaw: "debit", normalizedDescription: "SWIGGY")
    let key2 = makeDedupeKey(date: date, amountMinor: 4500, directionRaw: "debit", normalizedDescription: "SWIGGY")
    #expect(key1 == key2)
  }

  @Test func dedupeKeyDiffersOnAmount() {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let key1 = makeDedupeKey(date: date, amountMinor: 4500, directionRaw: "debit", normalizedDescription: "SWIGGY")
    let key2 = makeDedupeKey(date: date, amountMinor: 4600, directionRaw: "debit", normalizedDescription: "SWIGGY")
    #expect(key1 != key2)
  }

  @Test func dedupeKeyIgnoresTimeOfDay() {
    let calendar = Calendar(identifier: .gregorian)
    var components = DateComponents()
    components.year = 2026
    components.month = 4
    components.day = 1
    components.hour = 9
    let morning = calendar.date(from: components)!
    components.hour = 23
    let night = calendar.date(from: components)!

    let key1 = makeDedupeKey(date: morning, amountMinor: 100, directionRaw: "debit", normalizedDescription: "X", calendar: calendar)
    let key2 = makeDedupeKey(date: night, amountMinor: 100, directionRaw: "debit", normalizedDescription: "X", calendar: calendar)
    #expect(key1 == key2)
  }

  @Test func normalizeDescriptionStripsDigitsAndCollapsesWhitespace() {
    #expect(normalizeDescription("upi/p2m/412345/Swiggy  Order   99") == "UPI/PM//SWIGGY ORDER")
  }

  @Test func globMatchesWildcardBothEnds() {
    #expect(globMatches(pattern: "*SWIGGY*", value: "UPI/P2M/1234/SWIGGY/HDFC"))
    #expect(!globMatches(pattern: "*SWIGGY*", value: "UPI/P2M/1234/ZOMATO/HDFC"))
  }

  @Test func globMatchesPrefixSuffix() {
    #expect(globMatches(pattern: "UPI-*", value: "UPI-AMAZON-vpa@bank-note"))
    #expect(!globMatches(pattern: "UPI-*", value: "NEFT-AMAZON"))
  }

  @Test func globMatchesExactNoWildcard() {
    #expect(globMatches(pattern: "SWIGGY", value: "SWIGGY"))
    #expect(!globMatches(pattern: "SWIGGY", value: "SWIGGYORDER"))
  }
}

/// B1. These mutate the process-wide default time zone, which `TimeZone.current`
/// and `Calendar.current` read, so they must not run beside anything that reads
/// the ambient zone. `.serialized` orders them against each other; nothing else
/// in NomiCoreTests reads `.current`, which is what makes that sufficient.
@Suite(.serialized)
struct DedupeKeyTimeZoneTests {
  /// 2026-08-27T19:00:00Z. Deliberately chosen to fall on a different calendar
  /// day either side of the international date line: 27 Aug in
  /// America/Los_Angeles, 28 Aug in Pacific/Auckland — and 28 Aug in IST.
  private static let instant = Date(timeIntervalSince1970: 1_787_857_200)

  private func withDefaultTimeZone<T>(_ identifier: String, _ body: () -> T) -> T {
    let previous = NSTimeZone.default
    NSTimeZone.default = TimeZone(identifier: identifier)!
    defer { NSTimeZone.default = previous }
    return body()
  }

  private func defaultKey() -> String {
    makeDedupeKey(
      date: Self.instant,
      amountMinor: 45_000,
      directionRaw: Direction.debit.rawValue,
      normalizedDescription: "UPI/PM/SWIGGY"
    )
  }

  /// The bug, stated as a test: one instant, two devices, two keys. Fails
  /// against `main`, where the default calendar is `.current`.
  @Test func dedupeKeyIsIdenticalAcrossDeviceTimeZones() {
    let west = withDefaultTimeZone("America/Los_Angeles") { defaultKey() }
    let east = withDefaultTimeZone("Pacific/Auckland") { defaultKey() }
    #expect(west == east)
  }

  /// And the key both devices agree on is the IST one, not whichever zone
  /// happened to run first.
  @Test func defaultCalendarIsIndiaNotTheDevice() {
    let explicit = makeDedupeKey(
      date: Self.instant,
      amountMinor: 45_000,
      directionRaw: Direction.debit.rawValue,
      normalizedDescription: "UPI/PM/SWIGGY",
      calendar: NomiCalendar.india
    )
    let west = withDefaultTimeZone("America/Los_Angeles") { defaultKey() }
    let east = withDefaultTimeZone("Pacific/Auckland") { defaultKey() }
    #expect(west == explicit)
    #expect(east == explicit)
  }

  @Test func indiaCalendarIsGregorianKolkata() {
    #expect(NomiCalendar.india.identifier == .gregorian)
    #expect(NomiCalendar.india.timeZone.identifier == "Asia/Kolkata")
  }
}
