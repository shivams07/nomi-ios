import NomiCore
import SwiftUI

/// Card 9 (v5): last-sync status from `MailConnectionState`. The AC is
/// explicit that "disconnected" is shown as a fact, not an error — this row
/// never reaches for a colour outside the tertiary/quaternary text steps, on
/// any state, because `Design/**` has no dedicated error token and inventing
/// one is not this unit's call.
public struct SyncStatusRow: View {
  public let state: MailConnectionState

  public init(state: MailConnectionState) {
    self.state = state
  }

  public var body: some View {
    HStack(spacing: NomiSpacing.xxs) {
      Circle()
        .fill(dotColor)
        .frame(width: 6, height: 6)
      Text(Self.statusText(for: state))
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.textTertiary)
    }
  }

  private var dotColor: Color {
    switch state {
    case .connected: return NomiColor.textTertiary
    case .connecting, .disconnected, .failed: return NomiColor.textQuaternary
    }
  }

  static func statusText(for state: MailConnectionState, now: Date = Date()) -> String {
    switch state {
    case .connected(_, let lastSync):
      guard let lastSync else { return "Connected — not yet synced" }
      let relative = NomiFormatters.relativeTime.localizedString(for: lastSync, relativeTo: now)
      return "Synced \(relative)"
    case .connecting:
      return "Connecting…"
    case .disconnected:
      return "Mail not connected"
    case .failed:
      return "Last sync failed"
    }
  }
}

#Preview("Sync status — connected, dark") {
  SyncStatusRow(state: .connected(address: "shivam@example.com", lastSync: Date(timeIntervalSinceNow: -300)))
    .padding()
    .background(NomiColor.surfaceCanvas)
    .preferredColorScheme(.dark)
}

#Preview("Sync status — disconnected, dark") {
  SyncStatusRow(state: .disconnected)
    .padding()
    .background(NomiColor.surfaceCanvas)
    .preferredColorScheme(.dark)
}

#Preview("Sync status — connecting, dark") {
  SyncStatusRow(state: .connecting)
    .padding()
    .background(NomiColor.surfaceCanvas)
    .preferredColorScheme(.dark)
}

#Preview("Sync status — accessibility 3, dark") {
  SyncStatusRow(state: .connected(address: "shivam@example.com", lastSync: Date(timeIntervalSinceNow: -300)))
    .padding()
    .background(NomiColor.surfaceCanvas)
    .environment(\.dynamicTypeSize, .accessibility3)
    .preferredColorScheme(.dark)
}
