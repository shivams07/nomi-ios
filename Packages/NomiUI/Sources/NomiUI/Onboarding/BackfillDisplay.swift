import Foundation
import NomiCore

/// The copy and rows the First scan screen shows while a scan runs (S12c, artboard
/// "First scan"). Pure, so the row order, the plurals and the Need-a-look row are
/// tested without a view or a store.
enum BackfillDisplay {
  /// The line under the count: "214 transactions found so far".
  static func foundLine(created: Int) -> String {
    String(localized: "\(created) transactions found so far", bundle: .module)
  }

  /// The caption under the bar. The window is the scan's own, so it reads from the
  /// months the screen was given. Corrections 7 drops the month the engine cannot know.
  static func captionLine(months: Int) -> String {
    String(localized: "Checking your last \(months) months", bundle: .module)
  }

  /// At most three rows. One row per account with transactions, most transactions
  /// first (ties by title, so the order is stable). When anything waits for review,
  /// the "Need a look" row is always one of the three and goes last; the accounts
  /// fill the other two slots. With nothing to review, the accounts fill all three.
  static func rows(summaries: [AccountSummary], needsReview: Int) -> [(title: String, detail: String)] {
    let accounts = summaries
      .filter { $0.transactionCount > 0 }
      .sorted { lhs, rhs in
        if lhs.transactionCount != rhs.transactionCount {
          return lhs.transactionCount > rhs.transactionCount
        }
        return accountTitle(lhs) < accountTitle(rhs)
      }
      .map { summary -> (title: String, detail: String) in
        (
          title: accountTitle(summary),
          detail: String(localized: "\(summary.transactionCount) alerts", bundle: .module)
        )
      }

    guard needsReview > 0 else { return Array(accounts.prefix(3)) }
    let needALook = (
      title: String(localized: "Need a look", bundle: .module),
      detail: String(localized: "\(needsReview) to check", bundle: .module)
    )
    return Array(accounts.prefix(2)) + [needALook]
  }

  /// "HDFC Bank ••4471": the institution when there is one, else the account's own
  /// name, then the last four digits when the account has them.
  static func accountTitle(_ summary: AccountSummary) -> String {
    let name = summary.institution.isEmpty ? summary.displayName : summary.institution
    return summary.lastFour.isEmpty ? name : "\(name) ••\(summary.lastFour)"
  }
}
