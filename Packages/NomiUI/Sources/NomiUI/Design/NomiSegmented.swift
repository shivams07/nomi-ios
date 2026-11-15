import SwiftUI

/// A segmented control (F2a, I-17; canvas `.seg`). Segments are `height` tall
/// (44 by default) inside a 4 pt track.
///
/// `.onGround`: a `secondaryFill` track, the selected segment is `primary`
/// with a white label. `.onHero`: dark `heroControl` glass, the selected
/// segment is white at 26% with a white 36% stroke, and every label is white.
public struct NomiSegmented<Value: Hashable>: View {
  public enum Style: Sendable {
    case onGround
    case onHero
  }

  private let options: [(value: Value, title: String, systemImage: String?)]
  @Binding private var selection: Value
  private let style: Style
  private let height: CGFloat

  public init(
    _ options: [(value: Value, title: String, systemImage: String?)],
    selection: Binding<Value>,
    style: Style,
    height: CGFloat = 44
  ) {
    self.options = options
    self._selection = selection
    self.style = style
    self.height = height
  }

  public var body: some View {
    let row = HStack(spacing: 4) {
      ForEach(Array(options.enumerated()), id: \.offset) { _, option in
        segment(option)
      }
    }
    .padding(4)

    switch style {
    case .onGround:
      row.background(Capsule().fill(NomiColor.secondaryFill))
    case .onHero:
      row.nomiGlass(.heroControl, in: Capsule())
    }
  }

  private func segment(_ option: (value: Value, title: String, systemImage: String?)) -> some View {
    let isSelected = option.value == selection
    return Button {
      selection = option.value
    } label: {
      HStack(spacing: 8) {
        if let systemImage = option.systemImage {
          Image(systemName: systemImage)
        }
        Text(option.title)
      }
      .font(.custom(NomiFont.interSemiBold, size: 15, relativeTo: .subheadline))
      .foregroundStyle(labelColor(isSelected: isSelected))
      .frame(maxWidth: .infinity, minHeight: height)
      .background {
        if isSelected {
          Capsule().fill(selectedFill)
        }
      }
      .overlay {
        if isSelected && style == .onHero {
          Capsule().strokeBorder(NomiColor.heroText.opacity(0.36), lineWidth: 1)
        }
      }
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private var selectedFill: Color {
    switch style {
    case .onGround: return NomiColor.primary
    case .onHero: return NomiColor.heroText.opacity(0.26)
    }
  }

  private func labelColor(isSelected: Bool) -> Color {
    switch style {
    case .onGround:
      return isSelected ? NomiColor.onPrimary : NomiColor.ink
    case .onHero:
      return NomiColor.heroText
    }
  }
}

#Preview("Segmented · ground") {
  NomiSegmentedPreview(style: .onGround)
    .padding(20)
    .background(NomiColor.ground)
    .preferredColorScheme(.light)
}

#Preview("Segmented · hero") {
  NomiSegmentedPreview(style: .onHero)
    .padding(20)
    .background(NomiHeroGradient.gradient(height: 120, safeTop: 54))
    .preferredColorScheme(.light)
}

private struct NomiSegmentedPreview: View {
  let style: NomiSegmented<String>.Style
  @State private var selection = "Month"

  var body: some View {
    NomiSegmented(
      [
        (value: "Month", title: "Month", systemImage: nil),
        (value: "Year", title: "Year", systemImage: nil),
        (value: "All", title: "All", systemImage: nil),
      ],
      selection: $selection,
      style: style
    )
  }
}
