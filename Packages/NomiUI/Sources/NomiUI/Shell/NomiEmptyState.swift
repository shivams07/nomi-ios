import SwiftUI

// clt-harness: include

/// An empty state (F3, I-4; F2a): a centred block with a 56 pt `iconTile`
/// circle and `iconGlyph` symbol, a SemiBold 17 title, and a caption message
/// in `inkSecondary` at most 260 pt wide. The optional action is a small
/// primary pill (44 pt high, `primary` fill), the one next step.
///
/// The button shows only when both `actionTitle` and `action` are set. Callers
/// that need an "Add transaction" action hide it when
/// `\.nomiAddTransaction` is nil.
public struct NomiEmptyState: View {
  public let systemImage: String
  public let title: String
  public let message: String
  public let actionTitle: String?
  public let action: (() -> Void)?

  public init(
    systemImage: String,
    title: String,
    message: String,
    actionTitle: String? = nil,
    action: (() -> Void)? = nil
  ) {
    self.systemImage = systemImage
    self.title = title
    self.message = message
    self.actionTitle = actionTitle
    self.action = action
  }

  public var body: some View {
    VStack(spacing: 0) {
      Image(systemName: systemImage)
        .resizable()
        .scaledToFit()
        .frame(width: 26, height: 26)
        .foregroundStyle(NomiColor.iconGlyph)
        .frame(width: 56, height: 56)
        .background(Circle().fill(NomiColor.iconTile))
        .accessibilityHidden(true)

      Text(title)
        .nomiTextStyle(.headline)
        .foregroundStyle(NomiColor.ink)
        .multilineTextAlignment(.center)
        .padding(.top, NomiSpacing.sm)

      Text(message)
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.inkSecondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 260)
        .padding(.top, NomiSpacing.xxs)

      if let actionTitle, let action {
        Button(actionTitle, action: action)
          .buttonStyle(NomiSmallPillButtonStyle())
          .padding(.top, NomiSpacing.sm)
      }
    }
    .frame(maxWidth: .infinity)
  }
}

/// The small primary pill: 44 pt high, `primary` capsule, white SemiBold 14
/// label, fills its label's width. Dims at 40% when disabled.
private struct NomiSmallPillButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    NomiSmallPillBody(configuration: configuration)
  }
}

private struct NomiSmallPillBody: View {
  let configuration: ButtonStyleConfiguration

  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    configuration.label
      .font(.custom(NomiFont.interSemiBold, size: 14, relativeTo: .subheadline))
      .foregroundStyle(NomiColor.onPrimary)
      .padding(.horizontal, 18)
      .frame(minHeight: NomiSpacing.minTarget)
      .background(Capsule().fill(NomiColor.primary))
      .contentShape(Capsule())
      .opacity(isEnabled ? 1 : 0.4)
  }
}

#Preview("Empty state · Ledger · default") {
  NomiEmptyState(
    systemImage: "doc.text",
    title: "No transactions yet",
    message: "Transactions appear here once mail is connected, or add one by hand.",
    actionTitle: "Add transaction"
  ) {}
  .padding(.horizontal, 24)
  .padding(.top, 343)
  .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  .background(NomiColor.ground)
  .preferredColorScheme(.light)
}

#Preview("Empty state · Ledger · AX3") {
  NomiEmptyState(
    systemImage: "doc.text",
    title: "No transactions yet",
    message: "Transactions appear here once mail is connected, or add one by hand.",
    actionTitle: "Add transaction"
  ) {}
  .padding(.horizontal, 24)
  .padding(.top, 343)
  .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  .background(NomiColor.ground)
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.light)
}
