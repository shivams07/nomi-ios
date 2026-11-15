import SwiftUI

/// An inline status line, one message and an optional action (F2a, I-17;
/// canvas `.note`). `warning` is `warningTint` with `warning` text, `error` is
/// `errorTint` with `error` text, `ok` is `iconTile` with `navy` text. The
/// action sits on its own line under the message.
public struct NomiStatusNote: View {
  public enum Tone: Sendable {
    case warning
    case error
    case ok
  }

  public let text: String
  public let tone: Tone
  public let systemImage: String
  public let actionTitle: String?
  public let action: (() -> Void)?

  public init(
    _ text: String,
    tone: Tone,
    systemImage: String,
    actionTitle: String? = nil,
    action: (() -> Void)? = nil
  ) {
    self.text = text
    self.tone = tone
    self.systemImage = systemImage
    self.actionTitle = actionTitle
    self.action = action
  }

  private var fill: Color {
    switch tone {
    case .warning: return NomiColor.warningTint
    case .error: return NomiColor.errorTint
    case .ok: return NomiColor.iconTile
    }
  }

  private var ink: Color {
    switch tone {
    case .warning: return NomiColor.warning
    case .error: return NomiColor.error
    case .ok: return NomiColor.navy
    }
  }

  public var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: systemImage)
        .resizable()
        .scaledToFit()
        .frame(width: 18, height: 18)
        .foregroundStyle(ink)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 4) {
        Text(text)
          .nomiTextStyle(.subhead)
          .foregroundStyle(ink)
          .frame(maxWidth: .infinity, alignment: .leading)
          .fixedSize(horizontal: false, vertical: true)

        if let actionTitle, let action {
          Button(actionTitle, action: action)
            .nomiTextStyle(.label)
            .underline()
            .foregroundStyle(ink)
            .frame(minHeight: NomiSpacing.minTarget, alignment: .leading)
            .contentShape(Rectangle())
            .buttonStyle(.plain)
        }
      }
    }
    .padding(.vertical, 12)
    .padding(.horizontal, 14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      RoundedRectangle(cornerRadius: NomiRadius.inset, style: .continuous)
        .fill(fill)
    }
  }
}

#Preview("Status notes") {
  VStack(spacing: 12) {
    NomiStatusNote(
      "Gmail sign-in stopped working on 12 Nov. New alerts are not being read.",
      tone: .warning,
      systemImage: "envelope",
      actionTitle: "Reconnect"
    ) {}
    NomiStatusNote("That didn’t save. Check the amount and try again.", tone: .error, systemImage: "exclamationmark.circle")
    NomiStatusNote("iCloud is off, so Nomi is keeping everything on this iPhone only.", tone: .ok, systemImage: "icloud.slash")
  }
  .padding(20)
  .background(NomiColor.ground)
  .preferredColorScheme(.light)
}
