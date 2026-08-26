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
