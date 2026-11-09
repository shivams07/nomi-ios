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

/// The Dynamic Type rule for the tab bar (TB1), as plain values so the tests can
/// pin it. `NomiTabBarLayoutTests` checks it against the widths the device draws.
///
/// Each tab label is caption2-scaled Inter Medium. Its rendered width on iOS, at
/// 440 pt, from `NomiTabBarLayoutTests` (points):
///
/// | Size | Home | Ledger | Insights | Accounts |
/// |---|---|---|---|---|
/// | large | 31.3 | 37.3 | 41.3 | 50.0 |
/// | xLarge | 42.7 | 50.7 | 56.7 | 68.0 |
/// | xxLarge | 45.3 | 54.0 | 60.3 | 72.7 |
/// | xxxLarge | 51.0 | 60.7 | 67.7 | 81.7 |
///
/// At 375 pt the four tab slots and the `+` share 259 pt, once RootView's 24 pt side
/// margins, the bar's 8 pt padding and the 52 pt `+` come out. A slot is at least
/// 56 pt and widens to its label. The slots at `xxLarge` add to 245 pt, which fits
/// with 14 pt spare. At `xxxLarge` they add to 266.1 pt, which does not fit. So the
/// cap is `xxLarge`, the largest size whose five slots fit 375 pt with no overlap.
public enum NomiTabBarSizing {
  /// Sizes above this draw as this size, inside the bar only.
  public static let maximumTypeSize: DynamicTypeSize = .xxLarge
  /// The narrowest a tab slot may be: the artboard's 56 pt. A slot widens to fit
  /// a longer label.
  public static let slotMinWidth: CGFloat = 56
  /// The `+` button's diameter.
  public static let addButtonWidth: CGFloat = 52
  /// The bar's own padding on each side, inside its glass.
  public static let barHorizontalPadding: CGFloat = 8

  public static func effectiveTypeSize(_ size: DynamicTypeSize) -> DynamicTypeSize {
    min(size, maximumTypeSize)
  }

  public static func slotWidth(forLabelWidth labelWidth: CGFloat) -> CGFloat {
    max(slotMinWidth, labelWidth)
  }

  /// The width left for the four tab slots once the screen's side margins, the
  /// bar's padding and the `+` are taken out. `sideMargin` is the margin the
  /// caller sets on the bar (24 on the artboards).
  public static func tabSpaceBudget(screenWidth: CGFloat, sideMargin: CGFloat) -> CGFloat {
    screenWidth - 2 * sideMargin - 2 * barHorizontalPadding - addButtonWidth
  }

  /// Whether the slots for all labels fit on one line in `budget`, with no overlap.
  public static func labelsFitOneLine(labelWidths: [CGFloat], budget: CGFloat) -> Bool {
    labelWidths.reduce(0) { $0 + slotWidth(forLabelWidth: $1) } <= budget
  }
}

/// One rendered frame in the tab bar, in global coordinates, for
/// `NomiTabBarLayoutTests`. `name` is `slot:<id>`, `label:<id>`, or `slot:add`.
/// Nothing in the app reads it.
struct NomiTabBarFrame: Equatable {
  let name: String
  let frame: CGRect
}

struct NomiTabBarFramesKey: PreferenceKey {
  static let defaultValue: [NomiTabBarFrame] = []

  static func reduce(value: inout [NomiTabBarFrame], nextValue: () -> [NomiTabBarFrame]) {
    value.append(contentsOf: nextValue())
  }
}

/// The floating tab bar (F3, I-4; SIMP §0). Five slots, icons with labels, and
/// the selected tab is a filled `primary` capsule. The centre slot is the "+"
/// button, which opens the transaction entry sheet.
///
/// The bar is at least 64 pt high, with 8 pt side padding and a 32 pt corner
/// radius, on `nomiGlass(.tabBar)`. Each tab is at least 56 pt wide and 48 pt
/// high, and widens to fit its label. The type size is capped at
/// `NomiTabBarSizing.maximumTypeSize`, so the bar stays a bounded height at every
/// size. The caller sets the side and bottom margins (24 and 22 on the artboards).
public struct NomiTabBar: View {
  private let leading: [NomiTabBarItem]
  private let trailing: [NomiTabBarItem]
  private let selectedID: String
  private let onSelect: (String) -> Void
  private let onAdd: () -> Void

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
    // The cap. It is applied to the row, so each tab's label and icon read the
    // capped size from `NomiTabItemContent`.
    .dynamicTypeSize(...NomiTabBarSizing.maximumTypeSize)
    .padding(.horizontal, NomiTabBarSizing.barHorizontalPadding)
    .frame(maxWidth: .infinity, minHeight: 64)
    .nomiGlass(.tabBar, in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
    .background {
      GeometryReader { proxy in
        Color.clear.preference(key: NomiTabBarHeightKey.self, value: proxy.size.height)
      }
    }
    .background {
      GeometryReader { proxy in
        Color.clear.preference(
          key: NomiTabBarFramesKey.self,
          value: [NomiTabBarFrame(name: "bar", frame: proxy.frame(in: .global))]
        )
      }
    }
  }

  private func tabItem(_ item: NomiTabBarItem) -> some View {
    let isSelected = item.id == selectedID
    return Button {
      onSelect(item.id)
    } label: {
      NomiTabItemContent(title: item.title, symbolName: item.symbolName, isSelected: isSelected)
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
        .frame(width: NomiTabBarSizing.addButtonWidth, height: NomiTabBarSizing.addButtonWidth)
        .background {
          GeometryReader { proxy in
            Color.clear.preference(
              key: NomiTabBarFramesKey.self,
              value: [NomiTabBarFrame(name: "slot:add", frame: proxy.frame(in: .global))]
            )
          }
        }
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

/// The icon and label inside one tab. A child view, so `@ScaledMetric` reads the
/// size `NomiTabBar` caps. A property wrapper declared on the bar itself would read
/// the size from outside the cap, and the icon would keep growing.
private struct NomiTabItemContent: View {
  let title: String
  let symbolName: String
  let isSelected: Bool

  @ScaledMetric(relativeTo: .caption2) private var glyphSize: CGFloat = 22

  var body: some View {
    VStack(spacing: 2) {
      Image(systemName: symbolName)
        .resizable()
        .scaledToFit()
        .frame(width: glyphSize, height: glyphSize)
      Text(title)
        .nomiTextStyle(.tabLabel)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .background {
          GeometryReader { proxy in
            Color.clear.preference(
              key: NomiTabBarFramesKey.self,
              value: [NomiTabBarFrame(name: "label:\(title)", frame: proxy.frame(in: .global))]
            )
          }
        }
    }
    .foregroundStyle(isSelected ? NomiColor.onPrimary : NomiColor.inkTab)
    .frame(minWidth: NomiTabBarSizing.slotMinWidth)
    .frame(minHeight: 48)
    .background {
      if isSelected {
        Capsule().fill(NomiColor.primary)
      }
    }
    .background {
      GeometryReader { proxy in
        Color.clear.preference(
          key: NomiTabBarFramesKey.self,
          value: [NomiTabBarFrame(name: "slot:\(title)", frame: proxy.frame(in: .global))]
        )
      }
    }
    .contentShape(Capsule())
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
