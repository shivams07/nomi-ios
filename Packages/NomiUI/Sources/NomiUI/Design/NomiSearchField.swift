import SwiftUI

/// A search field (F2a, I-17): 54 pt high (it grows with Dynamic Type),
/// `NomiRadius.inset` (18) corners, `card` fill and a 1 pt `separator` stroke.
/// The prompt is in `placeholder`.
public struct NomiSearchField: View {
  public let prompt: String
  @Binding private var text: String

  public init(prompt: String, text: Binding<String>) {
    self.prompt = prompt
    self._text = text
  }

  public var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(NomiColor.inkSecondary)
        .accessibilityHidden(true)

      TextField(
        text: $text,
        prompt: Text(prompt).foregroundStyle(NomiColor.placeholder)
      ) {
        Text(prompt)
      }
      .nomiTextStyle(.body)
      .foregroundStyle(NomiColor.ink)
    }
    .padding(.horizontal, NomiSpacing.sm)
    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
    .background {
      RoundedRectangle(cornerRadius: NomiRadius.inset, style: .continuous)
        .fill(NomiColor.card)
    }
    .overlay {
      RoundedRectangle(cornerRadius: NomiRadius.inset, style: .continuous)
        .strokeBorder(NomiColor.separator, lineWidth: 1)
    }
  }
}

#Preview("Search field") {
  NomiSearchField(prompt: "Search transactions", text: .constant(""))
    .padding(20)
    .background(NomiColor.ground)
    .preferredColorScheme(.light)
}
