import SwiftUI

/// A settings row with a title, an optional caption and a switch (F2a, I-17).
/// `isPending` replaces the switch with a spinner and disables the row, while
/// a change is being saved.
///
/// The switch is labelled with the title, hidden visually, so VoiceOver reads
/// the row's name rather than an unnamed switch.
public struct NomiToggleRow: View {
  public let title: String
  public let caption: String?
  public let isPending: Bool
  @Binding private var isOn: Bool

  public init(title: String, caption: String?, isOn: Binding<Bool>, isPending: Bool = false) {
    self.title = title
    self.caption = caption
    self.isPending = isPending
    self._isOn = isOn
  }

  public var body: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .nomiTextStyle(.rowTitle)
          .foregroundStyle(NomiColor.ink)
        if let caption {
          Text(caption)
            .nomiTextStyle(.caption)
            .foregroundStyle(NomiColor.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      if isPending {
        ProgressView()
          .accessibilityLabel(Text("Saving", bundle: .module))
      } else {
        Toggle(title, isOn: $isOn)
          .labelsHidden()
          .tint(NomiColor.navy)
      }
    }
    .frame(minHeight: NomiSpacing.rowMinHeight)
    .disabled(isPending)
  }
}

#Preview("Toggle rows") {
  VStack(spacing: 0) {
    NomiToggleRow(title: "Show amounts", caption: "On the Home screen", isOn: .constant(true))
    NomiToggleRow(title: "Daily reminder", caption: nil, isOn: .constant(false))
    NomiToggleRow(title: "Connect mail", caption: "Saving", isOn: .constant(true), isPending: true)
  }
  .padding(.horizontal, 16)
  .nomiCard()
  .padding(20)
  .background(NomiColor.ground)
  .preferredColorScheme(.light)
}
