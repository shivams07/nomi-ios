import Foundation
import XCTest
@testable import NomiUI

/// S3a: the pattern "Always use this for <merchant>" writes. A merchant name
/// wins when it normalises to at least three characters; otherwise the first
/// two words of the bank text that are not a payment rail and carry no digit.
final class MerchantRulePatternTests: XCTestCase {

  // MARK: - Pattern table

  func testPatternTable() {
    let rows: [(merchant: String?, normalized: String, expected: String?)] = [
      ("Ola", "UPI OLACABS ", "*OLA*"),
      (nil, "UPI SBI MERCHANT FOOD COURT ", "*SBI MERCHANT*"),
      (nil, "NEFT ", nil),
      ("Blue Tokai Coffee", "UPI BLUE TOKAI COFFEE ROASTERS ", "*BLUE TOKAI COFFEE*"),
    ]
    for row in rows {
      XCTAssertEqual(
        MerchantRulePattern.pattern(merchantName: row.merchant, normalizedDescription: row.normalized),
        row.expected,
        "merchant \(String(describing: row.merchant)), description \(row.normalized)"
      )
    }
  }

  func testShortMerchantFallsBackToTheBankTextWords() {
    XCTAssertEqual(
      MerchantRulePattern.pattern(merchantName: "AB", normalizedDescription: "UPI SBI MERCHANT FOOD COURT "),
      "*SBI MERCHANT*"
    )
  }

  func testEmptyMerchantAndNoUsableWordsGivesNil() {
    XCTAssertNil(MerchantRulePattern.pattern(merchantName: "  ", normalizedDescription: "POS ATM "))
  }

  func testDigitBearingWordsAreSkipped() {
    XCTAssertEqual(
      MerchantRulePattern.pattern(merchantName: nil, normalizedDescription: "IMPS 77 RAJ STORES FOO"),
      "*RAJ STORES*"
    )
  }

  // MARK: - Display name

  func testDisplayNameIsTheMerchantWhenItIsUsable() {
    XCTAssertEqual(
      MerchantRulePattern.displayName(merchantName: "Blue Tokai Coffee", normalizedDescription: "UPI BLUE TOKAI "),
      "Blue Tokai Coffee"
    )
  }

  func testDisplayNameFallsBackToTitleCasedWords() {
    XCTAssertEqual(
      MerchantRulePattern.displayName(merchantName: nil, normalizedDescription: "UPI SBI MERCHANT FOOD COURT "),
      "Sbi Merchant"
    )
  }

  func testDisplayNameMatchesThePatternBranchForAShortMerchant() {
    XCTAssertEqual(
      MerchantRulePattern.displayName(merchantName: "AB", normalizedDescription: "UPI SBI MERCHANT FOOD COURT "),
      "Sbi Merchant"
    )
  }
}
