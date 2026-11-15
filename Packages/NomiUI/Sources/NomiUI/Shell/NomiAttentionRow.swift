import SwiftUI

// clt-harness: include

/// An attention row (F3, I-4): a 40 pt `iconTile` circle with an `iconGlyph`
/// symbol, a title and an optional message, and a trailing chevron, on a
/// card. It is at least 44 pt high. Colour is never the only signal: the icon
/// and the text carry the meaning.
///
/// This is the label only. The caller wraps it in a Button or NavigationLink, or
/// passes `showsChevron: false` when the row does not navigate.
public struct NomiAttentionRow: View {
  public let systemImage: String
  public let title: String
  public let message: String?
  public let showsChevron: Bool

  public init(systemImage: String, title: String, message: String?, showsChevron: Bool = true) {
    self.systemImage = systemImage
    self.title = title
    self.message = message
    self.showsChevron = showsChevron
  }

  public var body: some View {
    HStack(spacing: 12) {
      Image(systemName: systemImage)
        .resizable()
        .scaledToFit()
        .frame(width: 20, height: 20)
        .foregroundStyle(NomiColor.iconGlyph)
        .frame(width: 40, height: 40)
        .background(Circle().fill(NomiColor.iconTile))
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .nomiTextStyle(.label)
          .foregroundStyle(NomiColor.dayHeader)
        if let message {
          Text(message)
            .nomiTextStyle(.rowTitle)
            .foregroundStyle(NomiColor.ink)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      if showsChevron {
        Image(systemName: "chevron.right")
          .resizable()
          .scaledToFit()
          .frame(width: 16, height: 16)
          .foregroundStyle(NomiColor.inkSecondary)
          .accessibilityHidden(true)
      }
    }
    .frame(maxWidth: .infinity, minHeight: NomiSpacing.minTarget, alignment: .leading)
    .nomiCard(padding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
  }
}

#Preview("Attention row · default") {
  VStack(spacing: 12) {
    NomiAttentionRow(systemImage: "tray", title: "Needs you", message: "2 transactions to review")
    NomiAttentionRow(systemImage: "checkmark.circle", title: "All caught up", message: nil)
    NomiAttentionRow(
      systemImage: "exclamationmark.triangle",
      title: "Saved data couldn’t be opened",
      message: "Nomi couldn’t open its saved data on 14 Nov 2026, so it started fresh.",
      showsChevron: false
    )
  }
  .padding(20)
  .background(NomiColor.ground)
  .preferredColorScheme(.light)
}

#Preview("Attention row · AX3") {
  VStack(spacing: 12) {
    NomiAttentionRow(systemImage: "tray", title: "Needs you", message: "2 transactions to review")
    NomiAttentionRow(systemImage: "checkmark.circle", title: "All caught up", message: nil)
    NomiAttentionRow(
      systemImage: "exclamationmark.triangle",
      title: "Saved data couldn’t be opened",
      message: "Nomi couldn’t open its saved data on 14 Nov 2026, so it started fresh.",
      showsChevron: false
    )
  }
  .padding(20)
  .background(NomiColor.ground)
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.light)
}
