import SwiftUI

// clt-harness: include

/// One tab in `NomiTabBar`.
public struct NomiTabBarItem: Identifiable, Equatable, Sendable {
  public let id: String
  public let title: String
  public let symbolName: String

  public init(id: String, title: String, symbolName: String) {
    self.id = id
    self.title = title
    self.symbolName = symbolName
  }
}

/// Publishes the tab bar's height, so the screen can pad its content above it.
public struct NomiTabBarHeightKey: PreferenceKey {
  public static let defaultValue: CGFloat = 0

  public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}

/// The floating tab bar (F3, I-4; SIMP §0). Five slots, icons with labels, and
/// the selected tab is a filled `primary` capsule. The centre slot is the "+"
/// button, which opens the transaction entry sheet.
///
/// The bar is at least 64 pt high, with 8 pt side padding and a 32 pt corner
/// radius, on `nomiGlass(.tabBar)`. Each item is 56 pt wide and at least 48 pt
/// high, so AX sizes grow the bar. The caller sets the side and bottom margins
/// (24 and 22 on the artboards).
public struct NomiTabBar: View {
  private let leading: [NomiTabBarItem]
  private let trailing: [NomiTabBarItem]
  private let selectedID: String
  private let onSelect: (String) -> Void
  private let onAdd: () -> Void

  @ScaledMetric(relativeTo: .caption2) private var glyphSize: CGFloat = 22

  public init(
    leading: [NomiTabBarItem],
    trailing: [NomiTabBarItem],
    selectedID: String,
    onSelect: @escaping (String) -> Void,
    onAdd: @escaping () -> Void
  ) {
    self.leading = leading
    self.trailing = trailing
    self.selectedID = selectedID
    self.onSelect = onSelect
    self.onAdd = onAdd
  }

  private static let cornerRadius: CGFloat = 32

  public var body: some View {
    HStack(spacing: 0) {
      ForEach(leading) { item in
        tabItem(item)
        Spacer(minLength: 0)
      }
      addButton
      ForEach(trailing) { item in
        Spacer(minLength: 0)
        tabItem(item)
      }
    }
    .padding(.horizontal, 8)
    .frame(maxWidth: .infinity, minHeight: 64)
    .nomiGlass(.tabBar, in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
    .background {
      GeometryReader { proxy in
        Color.clear.preference(key: NomiTabBarHeightKey.self, value: proxy.size.height)
      }
    }
  }

  private func tabItem(_ item: NomiTabBarItem) -> some View {
    let isSelected = item.id == selectedID
    return Button {
      onSelect(item.id)
    } label: {
      VStack(spacing: 2) {
        Image(systemName: item.symbolName)
          .resizable()
          .scaledToFit()
          .frame(width: glyphSize, height: glyphSize)
        Text(item.title)
          .nomiTextStyle(.tabLabel)
      }
      .foregroundStyle(isSelected ? NomiColor.onPrimary : NomiColor.inkTab)
      .frame(width: 56)
      .frame(minHeight: 48)
      .background {
        if isSelected {
          Capsule().fill(NomiColor.primary)
        }
      }
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
  }

  private var addButton: some View {
    Button(action: onAdd) {
      Image(systemName: "plus")
        .resizable()
        .scaledToFit()
        .frame(width: 22, height: 22)
        .foregroundStyle(NomiColor.onPrimary)
        .frame(width: 52, height: 52)
        .background {
          Circle()
            .fill(
              LinearGradient(
                colors: [NomiColor.navy, NomiColor.navyDeep],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
            .shadow(
              color: NomiShadow.plus.color,
              radius: NomiShadow.plus.radius,
              x: NomiShadow.plus.x,
              y: NomiShadow.plus.y
            )
        }
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Add transaction")
  }
}

#Preview("Tab bar · Home selected · default") {
  ZStack(alignment: .bottom) {
    NomiColor.ground.ignoresSafeArea()
    NomiTabBar(
      leading: [
        NomiTabBarItem(id: "home", title: "Home", symbolName: "house"),
        NomiTabBarItem(id: "ledger", title: "Ledger", symbolName: "list.bullet.rectangle"),
      ],
      trailing: [
        NomiTabBarItem(id: "insights", title: "Insights", symbolName: "chart.pie"),
        NomiTabBarItem(id: "accounts", title: "Accounts", symbolName: "creditcard"),
      ],
      selectedID: "home",
      onSelect: { _ in },
      onAdd: {}
    )
    .padding(.horizontal, 24)
    .padding(.bottom, 22)
  }
  .preferredColorScheme(.light)
}

#Preview("Tab bar · Accounts selected · AX3") {
  ZStack(alignment: .bottom) {
    NomiColor.ground.ignoresSafeArea()
    NomiTabBar(
      leading: [
        NomiTabBarItem(id: "home", title: "Home", symbolName: "house"),
        NomiTabBarItem(id: "ledger", title: "Ledger", symbolName: "list.bullet.rectangle"),
      ],
      trailing: [
        NomiTabBarItem(id: "insights", title: "Insights", symbolName: "chart.pie"),
        NomiTabBarItem(id: "accounts", title: "Accounts", symbolName: "creditcard"),
      ],
      selectedID: "accounts",
      onSelect: { _ in },
      onAdd: {}
    )
    .padding(.horizontal, 24)
    .padding(.bottom, 22)
  }
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.light)
}
