import Foundation
import NomiCore

// clt-harness: include

/// Which Home layout the sheet draws (HM1, S1b). Pure, so the matrix and the
/// order of the sheet are tested without a view.
enum HomeLayout {
  enum Mode: Equatable {
    /// No transactions yet and mail is not connected: the two onboarding cards.
    case firstRun
    /// The dashboard modules. `showAttention` puts the attention row first.
    case normal(showAttention: Bool)
  }

  /// The attention row goes to the top only when mail has failed, or when it was
  /// connected and is now disconnected (S1b step 7). A user who never connected
  /// gets the same row at the bottom, in place of the healthy line.
  static func showsTopAttention(mail: MailConnectionState, history: MailConnectionHistory) -> Bool {
    switch mail {
    case .failed:
      return true
    case .disconnected:
      return history.hasEverConnected
    case .connecting, .connected:
      return false
    }
  }

  /// Mail needs attention when it is disconnected or has failed. Only a home with
  /// no transactions and mail that needs attention is first-run.
  static func mode(mail: MailConnectionState, history: MailConnectionHistory, hasAnyTransaction: Bool) -> Mode {
    let needsAttention: Bool
    switch mail {
    case .disconnected, .failed:
      needsAttention = true
    case .connecting, .connected:
      needsAttention = false
    }
    if !hasAnyTransaction && needsAttention {
      return .firstRun
    }
    return .normal(showAttention: showsTopAttention(mail: mail, history: history))
  }

  /// One section of the Home sheet, in artboard order (S1b step 1).
  enum Section: Equatable, Hashable {
    case attention
    case leftToSpend
    case review
    case whereItWent
    case comingUp
    case recent
    case mailStatus
  }

  /// The sheet's sections, top to bottom. The attention row leads only when it
  /// is shown; the rest keeps the artboard's order either way.
  static func sections(showAttention: Bool) -> [Section] {
    let body: [Section] = [.leftToSpend, .review, .whereItWent, .comingUp, .recent, .mailStatus]
    return showAttention ? [.attention] + body : body
  }
}
