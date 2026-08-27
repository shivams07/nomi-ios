import Foundation
import XCTest

@testable import NomiIngest

/// Loads the `.eml` fixtures off disk.
///
/// `#filePath`-relative, not `Bundle.module`, because U0 froze
/// `NomiIngest/Package.swift` with no `resources:` declaration — the same
/// constraint U3 hit and solved the same way for `Fixtures/File/`.
///
/// The fixtures are real RFC 5322 messages on purpose. If Shivam drops saved
/// `.eml` files from his own mailbox into this directory they run through the
/// identical code path with no adapter, which is the form §2.5.2's instruction
/// can actually take.
enum MailFixtures {
  static func url(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures/Mail")
      .appendingPathComponent(name)
  }

  static func message(_ name: String, uid: UInt32 = 1) throws -> MailMessage {
    let data = try Data(contentsOf: url(name))
    return try RFC822Message.parse(data, uid: uid, uidValidity: 900_100)
  }

  /// Every bank fixture, in a stable order.
  static let packFixtures = [
    "sbi_debit_upi.eml", "sbi_credit_salary.eml",
    "hdfc_debit_split_cells.eml", "hdfc_debit_netbanking.eml",
    "icici_debit_nested_split.eml", "icici_credit_refund.eml",
    "axis_debit_atm.eml", "axis_credit_interest.eml",
    "kotak_debit_card.eml", "kotak_debit_upi_nbsp.eml",
  ]

  static let promotionalFixtures = [
    "promo_hdfc_cashback.eml", "promo_icici_loan.eml", "promo_sbi_fd.eml",
    "promo_axis_card.eml", "promo_kotak_insurance.eml",
  ]

  /// Same calendar and zone `MailDate` parses in, so an expected date in a test
  /// means the same instant the extractor produced.
  static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = MailDate.bankTimeZone
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    return calendar.date(from: components)!
  }
}
