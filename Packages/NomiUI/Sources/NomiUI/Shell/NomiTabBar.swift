import SwiftUI

// clt-harness: include

/// One tab in `NomiTabBar`. `title` is the accessibility label; the bar draws icons only.
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

/// Publishes the tab bar's height through a preference. RootView still reads it. The
/// value does not reach RootView (#169), so F3b reads `NomiTabBar`'s `onHeightChange`
/// instead, and this key goes with it.
public struct NomiTabBarHeightKey: PreferenceKey {
  public static let defaultValue: CGFloat = 0

  public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}

/// The floating tab bar's fixed geometry (F3a, I-16). The bar draws icons only, so none
/// of it depends on Dynamic Type.
public enum NomiTabBarMetrics {
  /// Every circle, the `+` included. A circle is also the tap target.
  public static let slot: CGFloat = 54
  /// Between neighbouring circles.
  public static let gap: CGFloat = 6
  /// Inside the capsule, on every side.
  public static let padding: CGFloat = 7
  /// One circle plus the padding above and below.
  public static let barHeight: CGFloat = 68
  /// Five circles, four gaps and the two paddings.
  public static let barWidth: CGFloat = 308
  /// From the physical bottom edge, ignoring the safe area. F3b places the bar with it.
  public static let bottomOffset: CGFloat = 26
}

/// One rendered frame in the tab bar, in global coordinates, for `NomiTabBarLayoutTests`.
/// `name` is `bar`, `slot:<id>` or `slot:add`. Nothing in the app reads it.
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

/// The floating tab bar (F3a; plan F3, "icons-only five-slot bar"). Two leading tabs,
/// the centre `+` that opens the transaction entry sheet, and two trailing tabs. The
/// bar is a fixed 308 x 68 pt capsule of glass. The selected tab is a black circle
/// with a white glyph; the `+` is a green gradient circle.
///
/// The bar is the same size at every Dynamic Type size, and Bold Text only thickens the
/// glyphs. The caller positions the bar; `NomiTabBarMetrics.bottomOffset` is the
/// artboard's placement for it.
///
/// `onHeightChange` receives the bar's height on appearance and whenever it changes, so
/// the screen can pad its content above the bar.
public struct NomiTabBar: View {
  private let leading: [NomiTabBarItem]
  private let trailing: [NomiTabBarItem]
  private let selectedID: String
  private let onSelect: (String) -> Void
  private let onAdd: () -> Void
  private let onHeightChange: ((CGFloat) -> Void)?

  @Environment(\.legibilityWeight) private var legibilityWeight

  public init(
    leading: [NomiTabBarItem],
    trailing: [NomiTabBarItem],
    selectedID: String,
    onSelect: @escaping (String) -> Void,
    onAdd: @escaping () -> Void,
    onHeightChange: ((CGFloat) -> Void)? = nil
  ) {
    self.leading = leading
    self.trailing = trailing
    self.selectedID = selectedID
    self.onSelect = onSelect
    self.onAdd = onAdd
    self.onHeightChange = onHeightChange
  }

  /// The SF Symbol's size inside its circle.
  private static let glyphSize: CGFloat = 22

  /// Medium for the glyphs, semibold when Bold Text is on.
  private var glyphWeight: Font.Weight {
    legibilityWeight == .bold ? .semibold : .medium
  }

  public var body: some View {
    HStack(spacing: NomiTabBarMetrics.gap) {
      ForEach(leading) { item in
        tabSlot(item)
      }
      addSlot
      ForEach(trailing) { item in
        tabSlot(item)
      }
    }
    .padding(NomiTabBarMetrics.padding)
    .frame(width: NomiTabBarMetrics.barWidth, height: NomiTabBarMetrics.barHeight)
    .nomiGlass(.tabBar, in: Capsule())
    .background {
      frameReporter("bar")
    }
    .background {
      GeometryReader { proxy in
        Color.clear.preference(key: NomiTabBarHeightKey.self, value: proxy.size.height)
      }
    }
    .background {
      GeometryReader { proxy in
        Color.clear
          .onAppear { onHeightChange?(proxy.size.height) }
          .onChange(of: proxy.size.height) { _, height in onHeightChange?(height) }
      }
    }
  }

  private func tabSlot(_ item: NomiTabBarItem) -> some View {
    let isSelected = item.id == selectedID
    return Button {
      onSelect(item.id)
    } label: {
      ZStack {
        if isSelected {
          Circle()
            .fill(NomiColor.primary.opacity(0.90))
            .overlay {
              Circle().strokeBorder(
                LinearGradient(colors: [NomiGlass.selectedHighlight, .clear], startPoint: .top, endPoint: .center),
                lineWidth: 1
              )
            }
        }
        glyph(item.symbolName)
          .foregroundStyle(isSelected ? NomiColor.onPrimary : NomiColor.inkTab)
      }
      .frame(width: NomiTabBarMetrics.slot, height: NomiTabBarMetrics.slot)
      .contentShape(Circle())
      .background {
        frameReporter("slot:\(item.id)")
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(item.title)
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
  }

  private var addSlot: some View {
    Button(action: onAdd) {
      glyph("plus")
        .foregroundStyle(NomiColor.onPrimary)
        .frame(width: NomiTabBarMetrics.slot, height: NomiTabBarMetrics.slot)
        .background {
          Circle().fill(
            LinearGradient(colors: [NomiGlass.addTop, NomiGlass.addBottom], startPoint: .top, endPoint: .bottom)
          )
        }
        .contentShape(Circle())
        .background {
          frameReporter("slot:add")
        }
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Add transaction")
  }

  private func glyph(_ symbolName: String) -> some View {
    Image(systemName: symbolName)
      .resizable()
      .scaledToFit()
      .fontWeight(glyphWeight)
      .frame(width: Self.glyphSize, height: Self.glyphSize)
  }

  private func frameReporter(_ name: String) -> some View {
    GeometryReader { proxy in
      Color.clear.preference(
        key: NomiTabBarFramesKey.self,
        value: [NomiTabBarFrame(name: name, frame: proxy.frame(in: .global))]
      )
    }
  }
}

#Preview("Tab bar · Home selected") {
  ZStack(alignment: .bottom) {
    NomiColor.ground.ignoresSafeArea()
    NomiTabBar(
      leading: [
        NomiTabBarItem(id: "home", title: "Home", symbolName: "house"),
        NomiTabBarItem(id: "activity", title: "Activity", symbolName: "text.alignleft"),
      ],
      trailing: [
        NomiTabBarItem(id: "insights", title: "Insights", symbolName: "chart.bar"),
        NomiTabBarItem(id: "plan", title: "Plan", symbolName: "target"),
      ],
      selectedID: "home",
      onSelect: { _ in },
      onAdd: {}
    )
    .padding(.bottom, NomiTabBarMetrics.bottomOffset)
  }
  .preferredColorScheme(.light)
}

#Preview("Tab bar · Plan selected · Bold AX3") {
  ZStack(alignment: .bottom) {
    NomiColor.ground.ignoresSafeArea()
    NomiTabBar(
      leading: [
        NomiTabBarItem(id: "home", title: "Home", symbolName: "house"),
        NomiTabBarItem(id: "activity", title: "Activity", symbolName: "text.alignleft"),
      ],
      trailing: [
        NomiTabBarItem(id: "insights", title: "Insights", symbolName: "chart.bar"),
        NomiTabBarItem(id: "plan", title: "Plan", symbolName: "target"),
      ],
      selectedID: "plan",
      onSelect: { _ in },
      onAdd: {}
    )
    .padding(.bottom, NomiTabBarMetrics.bottomOffset)
  }
  .environment(\.dynamicTypeSize, .accessibility3)
  .environment(\.legibilityWeight, .bold)
  .preferredColorScheme(.light)
}
