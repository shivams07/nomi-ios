import SwiftUI

/// The page title row (F2a, I-17; canvas `.h1`): a SemiBold 30 title on the
/// left, trailing controls on the right. The title is a header for VoiceOver
/// and wraps at Dynamic Type rather than clipping.
public struct NomiPageHeader<Trailing: View>: View {
  public let title: String
  private let trailing: Trailing

  public init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
    self.title = title
    self.trailing = trailing()
  }

  public var body: some View {
    HStack(alignment: .center, spacing: NomiSpacing.xs) {
      Text(title)
        .nomiTextStyle(.pageTitle)
        .foregroundStyle(NomiColor.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)

      trailing
    }
  }
}

public extension NomiPageHeader where Trailing == EmptyView {
  init(_ title: String) {
    self.init(title) { EmptyView() }
  }
}

#Preview("Page header") {
  VStack(alignment: .leading, spacing: 16) {
    NomiPageHeader("Budgets") {
      NomiNavIcon(systemName: "plus")
    }
    NomiPageHeader("Activity")
  }
  .padding(.horizontal, 16)
  .frame(maxWidth: .infinity, alignment: .leading)
  .background(NomiColor.ground)
  .preferredColorScheme(.light)
}
