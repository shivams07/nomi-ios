import SwiftUI

// clt-harness: include

/// A filter chip. It is 36 pt high, with a 44 pt tap area. Selected: `navy`
/// fill and `onPrimary` text. Unselected: `card` fill, a 1 pt `separator`
/// stroke and `ink` text. With a count, the title reads "Needs review · 3".
public struct NomiChip: View {
  public let title: String
  public let count: Int?
  public let isSelected: Bool
  public let action: () -> Void

  public init(title: String, count: Int? = nil, isSelected: Bool, action: @escaping () -> Void) {
    self.title = title
    self.count = count
    self.isSelected = isSelected
    self.action = action
  }

  private var label: String {
    guard let count else { return title }
    return "\(title) · \(count)"
  }

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: NomiRadius.chip, style: .continuous)
  }

  public var body: some View {
    Button(action: action) {
      Text(label)
        .nomiTextStyle(isSelected ? .chipSelected : .chip)
        .foregroundStyle(isSelected ? NomiColor.onPrimary : NomiColor.ink)
        .lineLimit(1)
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background {
          shape.fill(isSelected ? NomiColor.navy : NomiColor.card)
        }
        .overlay {
          if !isSelected {
            shape.strokeBorder(NomiColor.separator, lineWidth: 1)
          }
        }
        .frame(minHeight: NomiSpacing.minTarget)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

#Preview("Chips · default") {
  HStack(spacing: 4) {
    NomiChip(title: "All", isSelected: true) {}
    NomiChip(title: "Needs review", count: 3, isSelected: false) {}
    NomiChip(title: "Transport", isSelected: false) {}
  }
  .padding(20)
  .frame(maxWidth: .infinity, alignment: .leading)
  .background(NomiColor.ground)
  .preferredColorScheme(.light)
}

#Preview("Chips · AX3") {
  VStack(alignment: .leading, spacing: 4) {
    NomiChip(title: "All", isSelected: true) {}
    NomiChip(title: "Needs review", count: 3, isSelected: false) {}
    NomiChip(title: "Transport", isSelected: false) {}
  }
  .padding(20)
  .frame(maxWidth: .infinity, alignment: .leading)
  .background(NomiColor.ground)
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.light)
}
