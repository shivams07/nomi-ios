import XCTest
@testable import NomiUI

final class EntryAmountTests: XCTestCase {
  func testWholeRupeesParseToMinorUnits() {
    XCTAssertEqual(EntryAmount.minorUnits(from: "125"), 12500)
  }

  func testDecimalParsesToMinorUnits() {
    XCTAssertEqual(EntryAmount.minorUnits(from: "125.50"), 12550)
  }

  func testEmptyTextIsZero() {
    XCTAssertEqual(EntryAmount.minorUnits(from: ""), 0)
  }

  func testZeroTextIsZero() {
    XCTAssertEqual(EntryAmount.minorUnits(from: "0"), 0)
  }

  func testNonNumericTextIsZero() {
    XCTAssertEqual(EntryAmount.minorUnits(from: "abc"), 0)
  }

  func testTrailingDecimalPointParses() {
    XCTAssertEqual(EntryAmount.minorUnits(from: "125."), 12500)
  }

  func testFractionalPaiseRounds() {
    XCTAssertEqual(EntryAmount.minorUnits(from: "12.999"), 1300)
  }

  func testSanitizeStripsNonNumericCharacters() {
    XCTAssertEqual(EntryAmount.sanitizeInput("1a2b3"), "123")
  }

  func testSanitizeKeepsOnlyFirstDecimalPoint() {
    XCTAssertEqual(EntryAmount.sanitizeInput("12.5.6"), "12.56")
  }

  func testSanitizeIsIdempotentOnCleanInput() {
    XCTAssertEqual(EntryAmount.sanitizeInput("125.50"), "125.50")
  }
}
