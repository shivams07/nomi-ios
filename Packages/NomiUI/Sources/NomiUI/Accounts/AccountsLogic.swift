import Foundation
import NomiCore

/// Same shape as `CategoryFormGate` — extracted so "renaming to an empty
/// string is rejected in the sheet" is testable without constructing a view.
enum AccountRenameGate {
  static func isValid(name: String) -> Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

/// `NomiFormatters.amountString` always strips the sign (by design — most
/// callers add their own `+`/`` based on transaction direction, see
/// `TransactionRow`). A tracked balance has no direction to hang a sign off
/// of and can go negative on an overdrawn account, so this is the one place
/// that needs its own `-` prefix or a negative balance would render
/// indistinguishably from a positive one.
enum TrackedBalanceText {
  static func string(minor: Int) -> String {
    let sign = minor < 0 ? "-" : ""
    return sign + NomiFormatters.amountString(minor: minor)
  }
}

/// The "since <trackingSince>" caption beneath the tracked balance. `nil`
/// for an account with zero transactions (`InsightsStore.accountSummaries`
/// derives `trackingSince` from the earliest transaction date, so there is
/// nothing to date yet) — the caller omits the line entirely rather than
/// rendering "since" with no date.
enum TrackedBalanceCaption {
  static func sinceText(_ date: Date?) -> String? {
    guard let date else { return nil }
    return "since \(NomiFormatters.dayMonthYear.string(from: date))"
  }
}

/// Splits summaries into the always-visible list and the collapsed archived
/// section — pulled out so "archived accounts move to a collapsed section,
/// not out of existence" is a policy the tests can check directly.
enum AccountSectioning {
  static func active(_ summaries: [AccountSummary]) -> [AccountSummary] {
    summaries.filter { !$0.isArchived }
  }

  static func archived(_ summaries: [AccountSummary]) -> [AccountSummary] {
    summaries.filter { $0.isArchived }
  }
}
