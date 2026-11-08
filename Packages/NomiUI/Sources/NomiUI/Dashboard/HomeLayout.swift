import Foundation
import NomiCore

// clt-harness: include

/// Which Home layout the sheet draws (HM1). Pure, so the mail-by-transactions
/// matrix is tested without a view.
enum HomeLayout {
  enum Mode: Equatable {
    /// No transactions yet and mail is not connected: the two onboarding cards.
    case firstRun
    /// The dashboard modules. `showAttention` puts the sync banner first.
    case normal(showAttention: Bool)
  }

  /// Mail needs attention when it is disconnected or has failed. `connecting`
  /// and `connected` never show the banner. Only a home with no transactions
  /// and mail that needs attention is first-run.
  static func mode(mail: MailConnectionState, hasAnyTransaction: Bool) -> Mode {
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
    return .normal(showAttention: needsAttention)
  }
}
