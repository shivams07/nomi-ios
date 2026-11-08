import Foundation
import NomiCore

// clt-harness: include

/// The money labels on the Accounts screen (AC, DEC-06). Pure, so the sign,
/// caption and total rules are checked by the CLT harness and not by eye.
///
/// A card's tracked balance is stored negative when it holds purchases, so
/// it reduces the hero total. The screen shows the size of that debt with an
/// "Owed" caption rather than a minus sign, because a user reads "−₹18,420.50"
/// on a card as a credit balance. Every other account shows its signed value.
enum AccountBalanceDisplay {
  /// One row's amount. `minor` is what the amount prints (no sign for "Owed"),
  /// and `caption` is the line under it, or nil.
  struct Line: Equatable {
    let minor: Int
    let caption: String?
  }

  /// A card below zero is owed: it prints the absolute amount and says so.
  /// Every other account prints its signed balance, and a negative bank
  /// balance keeps its "−".
  static func line(kind: AccountKind, trackedMinor: Int) -> Line {
    if kind == .card && trackedMinor < 0 {
      return Line(minor: abs(trackedMinor), caption: "Owed")
    }
    return Line(minor: trackedMinor, caption: nil)
  }

  /// The caption under a row's amount. "Owed" wins over "Opening": the
  /// opening balance is still visible in the edit sheet. "Opening" appears
  /// only when a balance was set, and keeps its sign ("Opening −₹18,420.00").
  /// nil when neither applies.
  static func rowCaption(kind: AccountKind, trackedMinor: Int, openingMinor: Int?) -> String? {
    if let owed = line(kind: kind, trackedMinor: trackedMinor).caption {
      return owed
    }
    guard let openingMinor else { return nil }
    let sign = openingMinor < 0 ? "\u{2212}" : ""
    return "Opening " + sign + NomiFormatters.amountString(minor: openingMinor)
  }

  /// The hero total: the signed tracked balances of accounts that are not
  /// archived. Archiving an account moves the total by exactly that account's
  /// tracked balance, and the archive confirmation says so.
  static func total(_ summaries: [(isArchived: Bool, trackedMinor: Int)]) -> Int {
    summaries.reduce(0) { sum, summary in
      summary.isArchived ? sum : sum + summary.trackedMinor
    }
  }

  /// The opening-balance footer in the edit sheet, by kind (DEC-06). A user
  /// who types an owed amount as positive makes the total go the wrong way,
  /// so the card footer says to enter it as negative.
  static func openingBalanceFooter(kind: AccountKind) -> String {
    switch kind {
    case .card:
      return "What this card held before Nomi started tracking it. If you owed money, enter it as a negative amount, for example -18420.00."
    case .bank, .wallet:
      return "What this account held before Nomi started tracking it. Leave blank if you don't know."
    }
  }

  /// The archive confirmation (DEC-06): the existing line, then what archiving
  /// does to the Tracked balance.
  static let archiveMessage = "Transactions are kept. You can unarchive this account anytime. Archived accounts are left out of your Tracked balance. Their transactions stay in your history and totals."
}
