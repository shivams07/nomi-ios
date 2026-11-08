import SwiftUI

// clt-harness: include

/// H1, the hero scaffold (F3 of nomi-ios-build-plan, I-4).
///
/// One `ScrollView`, so the hero scrolls with the content. The nav row sits at
/// the safe-area top, 12 pt above the hero. The hero is followed by
/// `heroBottomSpacing`, then the ground sheet, whose top corners (32 pt) rise 24
/// pt into the hero. The sheet has 20 pt gutters and a 20 pt top padding. The
/// gradient runs behind the hero block, from the top of the screen down to the
/// block's bottom, with stops from `NomiHeroGradient`. The hero block declares
/// no minimum height.
///
/// Home passes `heroBottomSpacing: 12` and Accounts `40`. At a 54 pt safe-area
/// top these reproduce sheet tops 332 and 226, and hero heights 356 and 250.
public struct NomiHeroScaffold<NavRow: View, Hero: View, Sheet: View>: View {
  private let heroBottomSpacing: CGFloat
  private let navRow: NavRow
  private let hero: Hero
  private let sheet: Sheet

  public init(
    heroBottomSpacing: CGFloat,
    @ViewBuilder navRow: () -> NavRow,
    @ViewBuilder hero: () -> Hero,
    @ViewBuilder sheet: () -> Sheet
  ) {
    self.heroBottomSpacing = heroBottomSpacing
    self.navRow = navRow()
    self.hero = hero()
    self.sheet = sheet()
  }

  public var body: some View {
    #if os(iOS)
    scaffold.toolbar(.hidden, for: .navigationBar)
    #else
    scaffold
    #endif
  }

  /// `navigationBar` is not available on macOS, so the hide modifier above is
  /// iOS-only. The CLT harness compiles the macOS branch.
  private var scaffold: some View {
    GeometryReader { outer in
      ScrollView {
        VStack(spacing: 0) {
          heroBlock(safeTop: outer.safeAreaInsets.top)
          sheetBlock
        }
        .frame(maxWidth: .infinity)
      }
      .ignoresSafeArea(.container, edges: .top)
      .background(NomiColor.ground)
    }
    .background(NomiColor.ground.ignoresSafeArea())
  }

  /// The nav row, the hero and the spacer that the sheet rises into. The
  /// gradient is drawn by a GeometryReader behind the block, so it takes the
  /// block's measured height without any state.
  private func heroBlock(safeTop: CGFloat) -> some View {
    VStack(spacing: 0) {
      navRow
        .frame(height: NomiSpacing.navRowHeight)
        .padding(.horizontal, NomiSpacing.screenGutter)
      hero
        .padding(.horizontal, NomiSpacing.screenGutter)
        .padding(.top, 12)
      // The 24 pt overlap is part of the hero's height. The sheet rises into it.
      Color.clear
        .frame(height: heroBottomSpacing + NomiSpacing.heroSheetOverlap)
    }
    .padding(.top, safeTop)
    .frame(maxWidth: .infinity)
    .background {
      GeometryReader { block in
        NomiHeroGradient.gradient(height: block.size.height, safeTop: safeTop)
      }
    }
  }

  private var sheetBlock: some View {
    sheet
      .padding(.horizontal, NomiSpacing.screenGutter)
      .padding(.top, NomiSpacing.screenGutter)
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .background {
        UnevenRoundedRectangle(
          topLeadingRadius: NomiRadius.sheet,
          topTrailingRadius: NomiRadius.sheet,
          style: .continuous
        )
        .fill(NomiColor.ground)
        .shadow(
          color: NomiShadow.heroSheet.color,
          radius: NomiShadow.heroSheet.radius,
          x: NomiShadow.heroSheet.x,
          y: NomiShadow.heroSheet.y
        )
      }
      .offset(y: -NomiSpacing.heroSheetOverlap)
  }
}

/// Hides a chart at accessibility sizes (SIMP §1 rule 6). Put any chart in the
/// hero inside this slot. At `.accessibility3` and above it renders nothing.
///
/// This type sits at file scope, not inside `NomiHeroScaffold`. A nested type
/// in a generic type cannot be named without its generic arguments, so the
/// name is `NomiHeroChartSlot`.
public struct NomiHeroChartSlot<C: View>: View {
  private let content: C

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  public init(@ViewBuilder content: () -> C) {
    self.content = content()
  }

  public var body: some View {
    if dynamicTypeSize >= .accessibility3 {
      EmptyView()
    } else {
      content
    }
  }
}

#Preview("Hero scaffold · Home · default") {
  NomiHeroScaffold(heroBottomSpacing: 12) {
    HStack {
      NomiPeriodPill(title: "November 2026", style: .onHero) {
        Button("November 2026") {}
      }
      Spacer()
      NomiHeroIcon(systemName: "gearshape")
    }
  } hero: {
    VStack(alignment: .leading, spacing: 0) {
      Text("Spent")
        .nomiTextStyle(.subhead)
        .foregroundStyle(NomiColor.heroTextSecondary)
      NomiAmountText(minor: 6_482_424, context: .hero, style: .heroAmount)
      NomiChip(title: "up ₹6,420 vs last period", isSelected: false) {}
    }
  } sheet: {
    NomiAttentionRow(systemImage: "tray", title: "Needs you", message: "2 transactions to review")
  }
  .preferredColorScheme(.light)
}

#Preview("Hero scaffold · Home · AX3") {
  NomiHeroScaffold(heroBottomSpacing: 12) {
    HStack {
      NomiPeriodPill(title: "November 2026", style: .onHero) {
        Button("November 2026") {}
      }
      Spacer()
      NomiHeroIcon(systemName: "gearshape")
    }
  } hero: {
    VStack(alignment: .leading, spacing: 0) {
      Text("Spent")
        .nomiTextStyle(.subhead)
        .foregroundStyle(NomiColor.heroTextSecondary)
      NomiAmountText(minor: 6_482_424, context: .hero, style: .heroAmount)
      NomiHeroChartSlot {
        Rectangle()
          .fill(NomiColor.heroText.opacity(0.2))
          .frame(height: 64)
      }
    }
  } sheet: {
    NomiAttentionRow(systemImage: "tray", title: "Needs you", message: "2 transactions to review")
  }
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.light)
}
