import NomiCore
import NomiPreview
import SwiftData
import SwiftUI

/// The Plan tab (S7; approved `Plan (Budgets + Recurring)` artboard). A short Moss
/// hero carries the month's left-to-spend figure and its pace bar. The ground sheet
/// under it holds the Budgets tiles, the suggestion, the Recurring list and the
/// budget-alerts switch. The initializer is final (F3b): RootView builds it.
public struct PlanScreen: View {
  public let budgetStore: BudgetStore
  public let insightsStore: InsightsStore
  public let recurringStore: (any RecurringInsightsStore)?
  @Binding public var notificationSettings: NotificationSettings
  public let isRequestingNotificationPermission: Bool
  /// G4. The composition root's cache generation. Stored and never read: a new
  /// value re-renders the screen, and `.task(id:)` reloads the model.
  public let refreshToken: Int

  @Query(sort: \NomiCore.Category.sortIndex) private var categories: [NomiCore.Category]
  @Query private var budgetRows: [NomiCore.Budget]
  @State private var model: PlanModel
  @State private var editingCategory: NomiCore.Category?
  @State private var suggestedCategory: NomiCore.Category?
  @State private var isAddingBudget = false
  @Environment(\.nomiShowLedger) private var showLedger
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  public init(
    budgetStore: BudgetStore,
    insightsStore: InsightsStore,
    recurringStore: (any RecurringInsightsStore)?,
    notificationSettings: Binding<NotificationSettings>,
    isRequestingNotificationPermission: Bool,
    refreshToken: Int
  ) {
    self.budgetStore = budgetStore
    self.insightsStore = insightsStore
    self.recurringStore = recurringStore
    _notificationSettings = notificationSettings
    self.isRequestingNotificationPermission = isRequestingNotificationPermission
    self.refreshToken = refreshToken
    _model = State(initialValue: PlanModel(insightsStore: insightsStore, recurringStore: recurringStore))
  }

  public var body: some View {
    NomiHeroScaffold(heroBottomSpacing: 12) {
      navRow
    } hero: {
      hero
    } sheet: {
      sheet
    }
    .task(id: refreshToken) { model.load() }
    .sheet(item: $editingCategory) { category in
      BudgetEditorSheet(
        budgetStore: budgetStore,
        category: category,
        availableCategories: [],
        currentAmountMinor: amountMinor(for: category.id),
        onSaved: { model.load() }
      )
    }
    .sheet(item: $suggestedCategory) { category in
      BudgetEditorSheet(
        budgetStore: budgetStore,
        category: category,
        availableCategories: [],
        currentAmountMinor: 0,
        onSaved: { model.load() }
      )
    }
    .sheet(isPresented: $isAddingBudget) {
      BudgetEditorSheet(
        budgetStore: budgetStore,
        category: nil,
        availableCategories: unbudgetedCategories,
        currentAmountMinor: 0,
        onSaved: { model.load() }
      )
    }
  }

  // MARK: - Derived

  private var budgetedCategoryIDs: Set<UUID> {
    Set(budgetRows.map(\.categoryID))
  }

  private var unbudgetedCategories: [NomiCore.Category] {
    categories.filter { !budgetedCategoryIDs.contains($0.id) }
  }

  private func amountMinor(for categoryID: UUID) -> Int {
    budgetRows.first { $0.categoryID == categoryID }?.amountMinor ?? 0
  }

  private var currentMonth: (year: Int, month: Int) {
    let parts = model.calendar.dateComponents([.year, .month], from: model.now())
    return (parts.year ?? 1970, parts.month ?? 1)
  }

  // MARK: - Hero

  /// The nav row: the title and the "+" that opens the create sheet. The "+" shows
  /// only while a category has no budget, as on Budgets.
  private var navRow: some View {
    HStack {
      Text("Plan")
        .nomiTextStyle(.pageTitle)
        .foregroundStyle(NomiColor.heroText)
        .accessibilityAddTraits(.isHeader)
      Spacer(minLength: NomiSpacing.xs)
      if !unbudgetedCategories.isEmpty {
        Button {
          isAddingBudget = true
        } label: {
          NomiHeroIcon(systemName: "plus")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add budget")
      }
    }
  }

  @ViewBuilder
  private var hero: some View {
    if let totals = model.totals {
      heroFigures(totals)
    } else if model.progress?.isEmpty == true {
      VStack(alignment: .leading, spacing: NomiSpacing.xs) {
        Text("No budgets yet")
          .nomiTextStyle(.heroTitle)
          .foregroundStyle(NomiColor.heroText)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, NomiSpacing.md)
    }
  }

  private func heroFigures(_ totals: BudgetTotals.Totals) -> some View {
    let daysLeft = PlanLogic.daysLeft(today: model.now(), calendar: model.calendar)
    let remaining = totals.remainingMinor
    let perDay = PlanLogic.perDay(remainingMinor: remaining, daysLeft: daysLeft)
    let pace = PlanLogic.pace(today: model.now(), month: currentMonth, calendar: model.calendar)
    return VStack(alignment: .leading, spacing: 0) {
      Text("Left to spend in \(PlanLogic.monthName(model.now(), calendar: model.calendar))")
        .font(.custom(NomiFont.interMedium, size: 14, relativeTo: .subheadline))
        .foregroundStyle(NomiColor.heroText)
        .padding(.top, NomiSpacing.md)
      NomiAmountText(minor: max(0, remaining), context: .hero, style: .heroAmount)
        .padding(.top, NomiSpacing.xs)
      heroChips(
        daysLeft: daysLeft,
        second: remaining >= 0
          ? "\(PlanLogic.money(minor: perDay * 100)) a day keeps you under"
          : "Over by \(PlanLogic.money(minor: remaining))"
      )
      .padding(.top, NomiSpacing.xs)

      NomiProgressBar(fraction: totals.fraction, height: 10, onHero: true)
        .overlay(alignment: .leading) {
          GeometryReader { proxy in
            Rectangle()
              .fill(NomiColor.ink)
              .frame(width: 2, height: 20)
              .position(x: min(max(pace, 0), 1) * proxy.size.width, y: proxy.size.height / 2)
              .accessibilityHidden(true)
          }
        }
        .padding(.top, NomiSpacing.md)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// The bar's labels: spent, the mark, and the budget. They sit on the ground sheet under
  /// the hero, not in it. On the Plan hero the row falls in the band where no text colour
  /// clears 4.5:1 (Large: y 287 to 309 on a 62 pt safe top; AX3 lower still), so the moss900
  /// text goes on ground, where it passes at every size.
  private func labelRow(_ totals: BudgetTotals.Totals) -> some View {
    let spent = "\(PlanLogic.money(minor: totals.spentMinor)) spent"
    let mark = "Mark: where today should be"
    let budget = PlanLogic.money(minor: totals.budgetMinor)
    return ViewThatFits(in: .horizontal) {
      HStack(alignment: .firstTextBaseline) {
        Text(spent)
        Spacer(minLength: NomiSpacing.xs)
        Text(mark)
          .multilineTextAlignment(.center)
        Spacer(minLength: NomiSpacing.xs)
        Text(budget)
      }
      VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
        Text(spent)
        Text(mark)
        Text(budget)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .font(.custom(NomiFont.interSemiBold, size: 12, relativeTo: .caption))
    .foregroundStyle(NomiColor.navyDeep)
    .fixedSize(horizontal: false, vertical: true)
    .accessibilityElement(children: .combine)
  }

  /// The two hero chips side by side at normal sizes, stacked when they do not fit,
  /// so neither is truncated at accessibility sizes.
  private func heroChips(daysLeft: Int, second: String) -> some View {
    let first = "\(daysLeft) days left"
    return ViewThatFits(in: .horizontal) {
      HStack(spacing: NomiSpacing.xs) {
        heroChip(first)
        heroChip(second)
      }
      VStack(alignment: .leading, spacing: NomiSpacing.xs) {
        heroChip(first)
        heroChip(second)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func heroChip(_ text: String) -> some View {
    Text(text)
      .nomiTextStyle(.heroChip)
      .foregroundStyle(NomiColor.heroText)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .nomiGlass(.heroControl, in: Capsule())
  }

  // MARK: - Sheet

  private var sheet: some View {
    VStack(alignment: .leading, spacing: NomiSpacing.md) {
      if let totals = model.totals {
        labelRow(totals)
      }
      budgetsSection
      if let suggestion = model.suggestion,
        let category = categories.first(where: { $0.id == suggestion.slice.id })
      {
        suggestionRow(category: category, averageMinor: suggestion.averageMinor)
      }
      recurringSection
      alertsCard
    }
  }

  @ViewBuilder
  private var budgetsSection: some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xs) {
      HStack(alignment: .firstTextBaseline) {
        Text("Budgets")
          .nomiTextStyle(.title)
          .foregroundStyle(NomiColor.ink)
          .accessibilityAddTraits(.isHeader)
        Spacer(minLength: NomiSpacing.xs)
        if let reset = PlanLogic.firstOfNextMonth(after: model.now(), calendar: model.calendar) {
          Text("Monthly · resets \(PlanLogic.dayMonth(reset, calendar: model.calendar))")
            .nomiTextStyle(.caption)
            .foregroundStyle(NomiColor.inkSecondary)
        }
      }
      if model.progress == nil {
        NomiLoadFailedCard(message: "Budgets didn’t load.") {
          model.load()
        }
      } else if let progress = model.progress, progress.isEmpty {
        NomiEmptyState(
          systemImage: "target",
          title: "Plan what you spend",
          message: "Set a monthly budget for a category and Nomi tracks what is left.",
          actionTitle: unbudgetedCategories.isEmpty ? nil : "Add a budget"
        ) {
          isAddingBudget = true
        }
        .frame(maxWidth: .infinity)
        .padding(.top, NomiSpacing.sm)
      } else if let progress = model.progress {
        LazyVGrid(
          columns: Array(
            repeating: GridItem(.flexible(), spacing: NomiSpacing.cardGap),
            count: PlanLogic.budgetColumns(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
          ),
          spacing: NomiSpacing.cardGap
        ) {
          ForEach(progress) { item in
            budgetTile(for: item)
          }
        }
      }
    }
  }

  private func budgetTile(for item: BudgetProgress) -> some View {
    let remaining = item.budgetMinor - item.spentMinor
    let state = NomiBudgetState.of(spentMinor: item.spentMinor, budgetMinor: item.budgetMinor)
    return Button {
      if let category = categories.first(where: { $0.id == item.id }) {
        editingCategory = category
      }
    } label: {
      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .firstTextBaseline, spacing: NomiSpacing.xxs) {
          Text(item.categoryName)
            .nomiTextStyle(.rowTitle)
            .foregroundStyle(NomiColor.ink)
            .lineLimit(PlanLogic.tileNameLineLimit(item.categoryName))
            .minimumScaleFactor(0.7)
            .truncationMode(.tail)
          Spacer(minLength: 0)
          if let tag = state.tagText {
            NomiTag(tag, tone: state == .over ? .error : .warning)
          }
        }
        NomiAmountText(minor: item.spentMinor, style: .amountLarge)
          .padding(.top, NomiSpacing.xxs)
        NomiProgressBar(fraction: item.fraction, state: state)
          .padding(.top, NomiSpacing.xs)
        tileCaption(remaining: remaining)
          .padding(.top, NomiSpacing.xs)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .nomiCard(padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14))
    }
    .buttonStyle(.plain)
    .contextMenu {
      if NomiShowLedgerLogic.showsControl(isWired: showLedger != nil) {
        Button("Show transactions") { showLedger?(.category(item.id)) }
      }
    }
    .accessibilityLabel(
      BudgetTileSpeech.label(
        name: item.categoryName,
        spentMinor: item.spentMinor,
        remainingMinor: remaining,
        fraction: item.fraction
      )
    )
  }

  /// "₹41 left of ₹5,000", or "₹965 over ₹2,600" in error text behind a "!" glyph,
  /// so over-budget never rests on colour alone.
  @ViewBuilder
  private func tileCaption(remaining: Int) -> some View {
    if remaining < 0 {
      HStack(spacing: NomiSpacing.xxs) {
        Text("!")
          .font(.custom(NomiFont.interSemiBold, size: 10, relativeTo: .caption2))
          .foregroundStyle(NomiColor.onPrimary)
          .frame(width: 14, height: 14)
          .background(Circle().fill(NomiColor.error))
          .accessibilityHidden(true)
        Text(tileCaptionText(remaining: remaining))
          .nomiTextStyle(.footnote)
          .foregroundStyle(NomiColor.error)
      }
    } else {
      Text(tileCaptionText(remaining: remaining))
        .nomiTextStyle(.footnote)
        .foregroundStyle(NomiColor.inkSecondary)
    }
  }

  private func tileCaptionText(remaining: Int) -> String {
    remaining < 0 ? "\(PlanLogic.money(minor: remaining)) over" : "\(PlanLogic.money(minor: remaining)) left"
  }

  private func suggestionRow(category: NomiCore.Category, averageMinor: Int) -> some View {
    Button {
      suggestedCategory = category
    } label: {
      HStack(spacing: NomiSpacing.sm) {
        Image(systemName: "plus")
          .foregroundStyle(NomiColor.ink)
          .frame(width: 40, height: 40)
          .background(Circle().fill(NomiColor.iconTile))
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text("Budget another category")
            .nomiTextStyle(.rowTitle)
            .foregroundStyle(NomiColor.ink)
          Text("\(category.name) averaged \(PlanLogic.money(minor: averageMinor)) over 3 months")
            .nomiTextStyle(.caption)
            .foregroundStyle(NomiColor.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: "chevron.right")
          .foregroundStyle(NomiColor.inkSecondary)
          .accessibilityHidden(true)
      }
      .nomiCard(padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14))
    }
    .buttonStyle(.plain)
  }

  // MARK: - Recurring

  @ViewBuilder
  private var recurringSection: some View {
    if model.recurringState != .unavailable {
      VStack(alignment: .leading, spacing: NomiSpacing.xs) {
        HStack(alignment: .firstTextBaseline) {
          Text("Recurring")
            .nomiTextStyle(.title)
            .foregroundStyle(NomiColor.ink)
            .accessibilityAddTraits(.isHeader)
          Spacer(minLength: NomiSpacing.xs)
          if model.recurringState == .loaded, !model.series.isEmpty {
            Text("\(PlanLogic.money(minor: model.monthlyRecurringMinor)) a month")
              .nomiTextStyle(.caption)
              .foregroundStyle(NomiColor.inkSecondary)
          }
        }
        switch model.recurringState {
        case .unavailable:
          EmptyView()
        case .failed:
          NomiLoadFailedCard(message: "Recurring payments didn’t load.") {
            model.load()
          }
        case .loaded:
          if model.series.isEmpty {
            Text("Repeating charges Nomi finds in your transactions will appear here.")
              .nomiTextStyle(.caption)
              .foregroundStyle(NomiColor.inkSecondary)
              .padding(.horizontal, NomiSpacing.xxs)
          } else {
            seriesCard
          }
        }
        if model.dismissFailed {
          NomiStatusNote(
            "That payment could not be hidden. Try again.",
            tone: .error,
            systemImage: "exclamationmark.circle"
          )
        }
        Text("Nomi finds recurring payments from three or more charges at a steady interval. Swipe one away if it is wrong.")
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.inkSecondary)
          .padding(.horizontal, NomiSpacing.xxs)
      }
    }
  }

  private var seriesCard: some View {
    VStack(spacing: 0) {
      ForEach(Array(model.series.enumerated()), id: \.element.id) { index, series in
        if index > 0 {
          Divider().padding(.leading, 68)
        }
        PlanRecurringRow(
          series: series,
          verb: RecurringCopy.verb(categoryName: series.category?.name),
          subtitle: RecurringCopy.subtitle(
            verb: RecurringCopy.verb(categoryName: series.category?.name),
            nextExpected: series.nextExpected,
            calendar: model.calendar
          ),
          onOpen: { showLedger?(.search(series.label)) },
          onDismiss: { model.dismiss(seriesID: series.id) },
          showsOpen: NomiShowLedgerLogic.showsControl(isWired: showLedger != nil)
        )
      }
    }
    .nomiCard(padding: EdgeInsets())
    .clipShape(RoundedRectangle(cornerRadius: NomiRadius.card, style: NomiRadius.cardSheetStyle))
  }

  // MARK: - Alerts

  private var alertsCard: some View {
    NomiToggleRow(
      title: "Budget alerts",
      caption: "A notification at 90% and when you go over",
      isOn: $notificationSettings.budgetAlertsEnabled,
      isPending: isRequestingNotificationPermission
    )
    .nomiCard(padding: EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
  }
}

/// One recurring row. The row opens the Activity search for its label. Dragging it
/// left reveals "Not recurring", and the same action is an accessibility action, so
/// the swipe is not the only way to dismiss.
private struct PlanRecurringRow: View {
  let series: RecurringSeries
  let verb: String
  let subtitle: String
  let onOpen: () -> Void
  let onDismiss: () -> Void
  let showsOpen: Bool

  @State private var offset: CGFloat = 0
  @State private var isRevealed = false

  private let revealWidth: CGFloat = 112

  var body: some View {
    ZStack(alignment: .trailing) {
      Button(role: .destructive) {
        onDismiss()
      } label: {
        Text("Not recurring")
          .nomiTextStyle(.rowTitle)
          .foregroundStyle(NomiColor.onPrimary)
          .frame(width: revealWidth)
          .frame(maxHeight: .infinity)
          .background(NomiColor.error)
      }
      .buttonStyle(.plain)
      .opacity(offset < 0 || isRevealed ? 1 : 0)
      .accessibilityHidden(true)

      rowContent
        .background(NomiColor.card)
        .offset(x: offset)
        .simultaneousGesture(
          DragGesture(minimumDistance: 16)
            .onChanged { value in
              guard abs(value.translation.width) > abs(value.translation.height) else { return }
              let base: CGFloat = isRevealed ? -revealWidth : 0
              offset = min(0, max(-PlanLogic.fullSwipeWidth, base + value.translation.width))
            }
            .onEnded { value in
              switch PlanLogic.recurringSwipeOutcome(translationWidth: value.translation.width, isRevealed: isRevealed) {
              case .dismiss:
                isRevealed = false
                withAnimation(.snappy) { offset = 0 }
                onDismiss()
              case .reveal:
                isRevealed = true
                withAnimation(.snappy) { offset = -revealWidth }
              case .rest:
                isRevealed = false
                withAnimation(.snappy) { offset = 0 }
              }
            }
        )
    }
    .clipped()
    .accessibilityAction(named: "Not recurring") {
      onDismiss()
    }
  }

  private var rowContent: some View {
    Button {
      if isRevealed {
        isRevealed = false
        withAnimation(.snappy) { offset = 0 }
      } else if showsOpen {
        onOpen()
      }
    } label: {
      HStack(spacing: NomiSpacing.sm) {
        badge
        VStack(alignment: .leading, spacing: 2) {
          Text(series.label)
            .nomiTextStyle(.rowTitle)
            .foregroundStyle(NomiColor.ink)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
          Text(subtitle)
            .nomiTextStyle(.caption)
            .foregroundStyle(NomiColor.inkSecondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        NomiAmountText(minor: series.amountMinor, style: .amount)
      }
      .padding(.horizontal, NomiSpacing.sm)
      .padding(.vertical, NomiSpacing.xs)
      .frame(minHeight: NomiSpacing.rowMinHeight)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private var badge: some View {
    if let category = series.category {
      NomiCategoryBadge(symbolName: category.symbolName, paletteSlot: category.paletteSlot, size: 40)
    } else {
      Text(String(series.label.prefix(1)).uppercased())
        .nomiTextStyle(.rowTitle)
        .foregroundStyle(NomiColor.ink)
        .frame(width: 40, height: 40)
        .background(Circle().fill(NomiColor.iconTile))
        .accessibilityHidden(true)
    }
  }
}

#Preview("Plan · budgets and recurring") {
  NavigationStack {
    PlanScreen(
      budgetStore: FakeBudgetStore(),
      insightsStore: FakeInsightsStore(),
      recurringStore: FakeRecurringStore(),
      notificationSettings: .constant(NotificationSettings(budgetAlertsEnabled: true)),
      isRequestingNotificationPermission: false,
      refreshToken: 0
    )
  }
  .modelContainer(for: [NomiCore.Category.self, NomiCore.Budget.self], inMemory: true)
  .preferredColorScheme(.light)
}
