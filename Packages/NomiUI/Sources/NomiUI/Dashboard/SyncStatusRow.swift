import NomiCore
import SwiftUI

/// What the Home banner says for a mail state that needs attention.
struct SyncAttention: Equatable {
  let systemImage: String
  let title: String
  let message: String?
}

/// Mail sync status (HM2). On Home it is the banner, shown only while mail is
/// disconnected or failed (`DashboardView` decides that and wraps the row in a
/// link to Connect mail). `.connecting` also gets the attention row. The
/// `.connected` state keeps the one-line caption, because Connect mail's
/// connected view (`ConnectMailScreen`) draws this row for it too.
///
/// The AC is explicit that "disconnected" is a fact to act on, not an error:
/// the copy says what to do, and the icon and text carry the meaning.
public struct SyncStatusRow: View {
  public let state: MailConnectionState

  public init(state: MailConnectionState) {
    self.state = state
  }

  public var body: some View {
    if let attention = Self.attention(for: state) {
      NomiAttentionRow(systemImage: attention.systemImage, title: attention.title, message: attention.message)
    } else {
      HStack(spacing: NomiSpacing.xxs) {
        Circle()
          .fill(NomiColor.inkSecondary)
          .frame(width: 6, height: 6)
          .accessibilityHidden(true)
        Text(Self.statusText(for: state))
          .nomiTextStyle(.footnote)
          .foregroundStyle(NomiColor.inkSecondary)
      }
    }
  }

  /// The attention copy for a state. `nil` for `.connected`, which has nothing
  /// to ask of the user.
  static func attention(for state: MailConnectionState) -> SyncAttention? {
    switch state {
    case .connected:
      return nil
    case .connecting:
      return SyncAttention(
        systemImage: "arrow.triangle.2.circlepath",
        title: "Connecting…",
        message: nil
      )
    case .disconnected:
      return SyncAttention(
        systemImage: "envelope.badge",
        title: "Mail disconnected",
        message: "Connect again to keep your numbers current."
      )
    case .failed(let error):
      return SyncAttention(
        systemImage: "exclamationmark.triangle",
        title: "Couldn’t reach your mail",
        message: failureMessage(for: error)
      )
    }
  }

  static func failureMessage(for error: MailError) -> String {
    switch error {
    case .authenticationFailed:
      return "Your mail provider refused the password. Connect again."
    case .connectionFailed:
      return "Check your connection, then try again."
    case .unknown:
      return "Try connecting again."
    }
  }

  static func statusText(for state: MailConnectionState, now: Date = Date()) -> String {
    switch state {
    case .connected(_, let lastSync):
      guard let lastSync else { return "Connected — not yet synced" }
      return "Synced \(relativeSyncPhrase(lastSync, now: now))"
    case .connecting:
      return "Connecting…"
    case .disconnected:
      return "Mail not connected"
    case .failed:
      return "Last sync failed"
    }
  }

  /// What follows "Synced", and the one implementation of the relative sync
  /// phrase. `MailAttentionLogic.lastSyncedPhrase` forwards here, so the Home
  /// row and the Connect mail card cannot drift apart. A `lastSync` less than a
  /// second before `now` has no age to report, and one after `now` (clock skew,
  /// or a sync stamped this instant) has a negative one, which the formatter
  /// reads as "in 1 hr.". Both read "just now".
  static func relativeSyncPhrase(_ lastSync: Date, now: Date) -> String {
    guard now.timeIntervalSince(lastSync) >= 1 else { return "just now" }
    return NomiFormatters.relativeTime.localizedString(for: lastSync, relativeTo: now)
  }
}

#Preview("Sync status · disconnected") {
  SyncStatusRow(state: .disconnected)
    .padding()
    .background(NomiColor.ground)
    .preferredColorScheme(.light)
}

#Preview("Sync status · failed") {
  SyncStatusRow(state: .failed(.connectionFailed))
    .padding()
    .background(NomiColor.ground)
    .preferredColorScheme(.light)
}

#Preview("Sync status · connecting") {
  SyncStatusRow(state: .connecting)
    .padding()
    .background(NomiColor.ground)
    .preferredColorScheme(.light)
}

#Preview("Sync status · connected caption") {
  SyncStatusRow(state: .connected(address: "shivam@example.com", lastSync: Date(timeIntervalSinceNow: -300)))
    .padding()
    .background(NomiColor.ground)
    .preferredColorScheme(.light)
}
