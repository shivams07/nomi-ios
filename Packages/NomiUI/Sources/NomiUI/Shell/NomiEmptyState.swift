import SwiftUI

// clt-harness: include

/// An empty state (F3, I-4): a 56 pt `iconTile` circle with an `iconGlyph`
/// symbol, a `headline` title, a centred `caption` message in `inkSecondary`,
/// and an optional full-width primary button (52 pt).
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
        .frame(maxWidth: 290)
        .padding(.top, NomiSpacing.xxs)

      if let actionTitle, let action {
        Button(actionTitle, action: action)
          .buttonStyle(NomiPrimaryButtonStyle(height: 52))
          .padding(.top, NomiSpacing.md)
      }
    }
    .frame(maxWidth: .infinity)
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
