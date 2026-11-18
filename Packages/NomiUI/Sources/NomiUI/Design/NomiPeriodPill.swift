import SwiftUI

// clt-harness: include

/// The period menu: a 44 pt pill with the period title and a down chevron.
/// `.onHero` is `heroControl` glass with white text. `.onGround` is a `card`
/// fill with a 1 pt `separator` stroke and navy text. The menu content is the
/// caller's.
public struct NomiPeriodPill<MenuContent: View>: View {
  public enum Style: Sendable {
    case onHero
    case onGround
  }

  public let title: String
  public let style: Style
  /// `false` (the default, every existing call site) keeps the title on one line.
  /// `true` lets the title wrap onto as many lines as it needs, so no word is cut.
  /// The Home hero sets it at accessibility sizes (HeroTotalCard.navRowStacks).
  public let wrapsTitle: Bool
  public let menu: MenuContent

  public init(
    title: String,
    style: Style,
    wrapsTitle: Bool = false,
    @ViewBuilder menu: () -> MenuContent
  ) {
    self.title = title
    self.style = style
    self.wrapsTitle = wrapsTitle
    self.menu = menu()
  }

  private var foreground: Color {
    switch style {
    case .onHero:
      return NomiColor.heroText
    case .onGround:
      return NomiColor.navy
    }
  }

  public var body: some View {
    Menu {
      menu
    } label: {
      HStack(spacing: 6) {
        titleText
        Image(systemName: "chevron.down")
          .resizable()
          .scaledToFit()
          .frame(width: 14, height: 14)
      }
      .foregroundStyle(foreground)
      .padding(.leading, 16)
      .padding(.trailing, 14)
      .frame(minHeight: NomiSpacing.navRowHeight)
      .background {
        pillBackground
      }
      .contentShape(Capsule())
    }
    // A wrapped title needs the label's full height. A Menu's label is otherwise
    // given its single-line height, so the second line falls outside the capsule
    // (PR 233, Lim, AX5). Off for every other caller, so their layout is unchanged.
    .fixedSize(horizontal: false, vertical: wrapsTitle)
    .accessibilityLabel("Choose period, \(title)")
  }

  @ViewBuilder
  private var titleText: some View {
    if wrapsTitle {
      Text(title)
        .nomiTextStyle(.rowTitle)
        .lineLimit(nil)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    } else {
      Text(title)
        .nomiTextStyle(.rowTitle)
    }
  }

  @ViewBuilder
  private var pillBackground: some View {
    switch style {
    case .onHero:
      Color.clear
        .nomiGlass(.heroControl, in: Capsule())
    case .onGround:
      Capsule()
        .fill(NomiColor.card)
        .overlay {
          Capsule().strokeBorder(NomiColor.separator, lineWidth: 1)
        }
    }
  }
}

#Preview("Period pill · default") {
  VStack(alignment: .leading, spacing: 16) {
    NomiPeriodPill(title: "November 2026", style: .onHero) {
      Button("November 2026") {}
      Button("October 2026") {}
    }
    .padding(20)
    .background(NomiHeroGradient.gradient(height: 120, safeTop: 54))
    NomiPeriodPill(title: "November 2026", style: .onGround) {
      Button("November 2026") {}
      Button("October 2026") {}
    }
  }
  .padding(20)
  .frame(maxWidth: .infinity, alignment: .leading)
  .background(NomiColor.ground)
  .preferredColorScheme(.light)
}

#Preview("Period pill · AX3") {
  VStack(alignment: .leading, spacing: 16) {
    NomiPeriodPill(title: "November 2026", style: .onHero) {
      Button("November 2026") {}
      Button("October 2026") {}
    }
    .padding(20)
    .background(NomiHeroGradient.gradient(height: 120, safeTop: 54))
    NomiPeriodPill(title: "November 2026", style: .onGround) {
      Button("November 2026") {}
      Button("October 2026") {}
    }
  }
  .padding(20)
  .frame(maxWidth: .infinity, alignment: .leading)
  .background(NomiColor.ground)
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.light)
}
