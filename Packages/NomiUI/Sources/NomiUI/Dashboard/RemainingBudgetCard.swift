import NomiCore
import SwiftUI

/// Left to spend (S1b step 2, the artboard's first card). The amount is what is
/// left of this month's budget, `max(0, budget − spent)`. A state tag shows when
/// spending is close to the budget or over it. A trailing pace caption gives the
/// days left and whole rupees a day. The bar and the caption under it come from
/// `BudgetTotals` (`BudgetsLogic.swift`), so they cannot disagree with Budgets.
///
/// Not `public`, same as `DashboardCard` next door, because its `state` takes
/// `DashboardWiring.BudgetModuleState`, and `DashboardWiring` is deliberately
/// internal (it is wiring, not API). Tapping the card opens the Plan tab
/// (`nomiShowPlan`), passed in as `onTap`.
struct RemainingBudgetCard: View {
  let state: DashboardWiring.BudgetModuleState
  /// How many categories have a budget this month, for the caption.
  let categoryCount: Int
  /// The viewed period's anchor. Its month decides the period end for the pace caption.
  let referenceDate: Date
  /// Opens the Plan tab. `nil` leaves the card non-interactive.
  let onTap: (() -> Void)?

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  init(
    state: DashboardWiring.BudgetModuleState,
    categoryCount: Int = 0,
    referenceDate: Date = Date(),
    onTap: (() -> Void)? = nil
  ) {
    self.state = state
    self.categoryCount = categoryCount
    self.referenceDate = referenceDate
    self.onTap = onTap
  }

  var body: some View {
    if let onTap {
      Button(action: onTap) { card }
        .buttonStyle(.plain)
    } else {
      card
    }
  }

  private var card: some View {
    DashboardCard {
      switch state {
      case .remaining(let totals):
        remainingContent(totals: totals)
      case .prompt:
        promptContent
      }
    }
  }

  private func remainingContent(totals: BudgetTotals.Totals) -> some View {
    let left = RemainingBudgetText.leftMinor(budgetMinor: totals.budgetMinor, spentMinor: totals.spentMinor)
    let tag = RemainingBudgetText.tag(spentMinor: totals.spentMinor, budgetMinor: totals.budgetMinor)
    let pace = Self.paceCaption(
      leftMinor: left,
      today: Date(),
      periodEnd: Self.periodEnd(for: referenceDate, calendar: NomiCalendar.india),
      calendar: NomiCalendar.india
    )
    let caption = RemainingBudgetText.caption(
      spentMinor: totals.spentMinor, budgetMinor: totals.budgetMinor, categoryCount: categoryCount)
    return VStack(alignment: .leading, spacing: NomiSpacing.xs) {
      // At accessibility sizes the tag goes under its label, so its words are not cut.
      let stacksTag = dynamicTypeSize.isAccessibilitySize
      if stacksTag {
        VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
          Text("Left to spend", bundle: .module)
            .nomiTextStyle(.label)
            .foregroundStyle(NomiColor.dayHeader)
          if let tag {
            NomiTag(tag.text, tone: tag.tone)
          }
        }
      } else {
        HStack(alignment: .center, spacing: NomiSpacing.xs) {
          Text("Left to spend", bundle: .module)
            .nomiTextStyle(.label)
            .foregroundStyle(NomiColor.dayHeader)
          Spacer(minLength: NomiSpacing.xs)
          if let tag {
            NomiTag(tag.text, tone: tag.tone)
          }
        }
      }
      HStack(alignment: .lastTextBaseline, spacing: NomiSpacing.xs) {
        NomiAmountText(minor: left, style: .displayValue)
        Spacer(minLength: NomiSpacing.xs)
        if let pace {
          Text(pace)
            .nomiTextStyle(.caption)
            .foregroundStyle(NomiColor.inkSecondary)
        }
      }
      NomiProgressBar(
        fraction: totals.fraction,
        state: NomiBudgetState.of(spentMinor: totals.spentMinor, budgetMinor: totals.budgetMinor)
      )
      .padding(.top, NomiSpacing.xxs)
      Text(caption)
        .nomiTextStyle(.footnote)
        .foregroundStyle(NomiColor.inkSecondary)
    }
    .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      RemainingBudgetText.accessibilityLabel(
        leftMinor: left, caption: caption, tagText: tag?.text, paceText: pace)
    )
  }

  /// No budgets set yet. The prompt is the card's own copy, with the chevron that
  /// says it opens something.
  private var promptContent: some View {
    HStack(spacing: NomiSpacing.xs) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Set a monthly budget")
          .nomiTextStyle(.headline)
          .foregroundStyle(NomiColor.ink)
        Text("Nomi warns you as you approach it")
          .nomiTextStyle(.footnote)
          .foregroundStyle(NomiColor.inkSecondary)
      }
      Spacer(minLength: NomiSpacing.xs)
      Image(systemName: "chevron.right")
        .resizable()
        .scaledToFit()
        .frame(width: 16, height: 16)
        .foregroundStyle(NomiColor.inkSecondary)
        .accessibilityHidden(true)
    }
    .accessibilityElement(children: .combine)
  }

  // MARK: - Pace

  /// "<d> days left · ₹<per day> a day", or nil once the period has ended, so a
  /// past month shows no pace at all rather than "0 days left".
  ///
  /// Days left count today and the period's last day, both inclusive. Per day is
  /// the left money divided by those days, floored to whole rupees (₹77, not the
  /// canvas's ₹78; Corrections 10). Over budget reads "₹0 a day".
  static func paceCaption(leftMinor: Int, today: Date, periodEnd: Date, calendar: Calendar) -> String? {
    let todayStart = calendar.startOfDay(for: today)
    let endStart = calendar.startOfDay(for: periodEnd)
    guard todayStart <= endStart else { return nil }
    let days = (calendar.dateComponents([.day], from: todayStart, to: endStart).day ?? 0) + 1
    let perDayRupees = leftMinor > 0 ? leftMinor / days / 100 : 0
    return String(
      localized: "\(days) days left · \(RemainingBudgetText.wholeRupees(perDayRupees)) a day",
      bundle: .module
    )
  }

  /// The last day of the anchor's month.
  static func periodEnd(for anchor: Date, calendar: Calendar) -> Date {
    let monthDays = calendar.range(of: .day, in: .month, for: anchor)?.count ?? 30
    let parts = calendar.dateComponents([.year, .month], from: anchor)
    return calendar.date(from: DateComponents(
      calendar: calendar, timeZone: calendar.timeZone,
      year: parts.year, month: parts.month, day: monthDays, hour: 12))!
  }
}

/// The Left to spend card's wording and rules, pure so the tests can reach them.
enum RemainingBudgetText {
  /// Over means strictly below zero. Exactly zero left is not over.
  static func isOver(remainingMinor: Int) -> Bool {
    remainingMinor < 0
  }

  /// `max(0, budget − spent)`. The amount on the card, never negative.
  static func leftMinor(budgetMinor: Int, spentMinor: Int) -> Int {
    max(0, budgetMinor - spentMinor)
  }

  /// The state tag: nothing under budget, "<pct>% of budget used" at 90% or more
  /// (warning), and "Over budget" once spending reaches the budget (error). The
  /// state comes from `NomiBudgetState`, which decides in integers.
  struct Tag: Equatable {
    let text: String
    let tone: NomiTag.Tone
  }

  static func tag(spentMinor: Int, budgetMinor: Int) -> Tag? {
    switch NomiBudgetState.of(spentMinor: spentMinor, budgetMinor: budgetMinor) {
    case .under:
      return nil
    case .close:
      let percent = spentMinor * 100 / budgetMinor
      return Tag(text: String(localized: "\(percent)% of budget used", bundle: .module), tone: .warning)
    case .over:
      return Tag(text: String(localized: "Over budget", bundle: .module), tone: .error)
    }
  }

  /// "₹12,279.00 spent of ₹13,600.00 budgeted across 4 categories".
  static func caption(spentMinor: Int, budgetMinor: Int, categoryCount: Int) -> String {
    String(
      localized: "\(NomiFormatters.amountString(minor: spentMinor)) spent of \(NomiFormatters.amountString(minor: budgetMinor)) budgeted across \(categoryCount) categories",
      bundle: .module
    )
  }

  /// Whole rupees with Indian grouping, for the pace caption ("₹1,321 a day").
  static func wholeRupees(_ rupees: Int) -> String {
    wholeRupeesFormatter.string(from: NSNumber(value: rupees)) ?? "₹\(rupees)"
  }

  private static let wholeRupeesFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_IN")
    formatter.numberStyle = .currency
    formatter.currencySymbol = "₹"
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 0
    return formatter
  }()

  /// The card is one element. Its label says what is left, the state word and the pace.
  static func accessibilityLabel(
    leftMinor: Int,
    caption: String,
    tagText: String?,
    paceText: String?
  ) -> String {
    var parts = ["Left to spend: \(NomiFormatters.amountString(minor: leftMinor))"]
    if let tagText { parts.append(tagText) }
    if let paceText { parts.append(paceText) }
    parts.append(caption)
    return parts.joined(separator: ". ")
  }
}

#Preview("Left to spend · under budget") {
  RemainingBudgetCard(
    state: .remaining(
      BudgetTotals.Totals(budgetMinor: 80000_00, spentMinor: 64824_00, remainingMinor: 15175_76, fraction: 0.81)
    ),
    categoryCount: 4
  )
  .padding()
  .background(NomiColor.ground)
  .preferredColorScheme(.light)
}

#Preview("Left to spend · close") {
  RemainingBudgetCard(
    state: .remaining(
      BudgetTotals.Totals(budgetMinor: 13600_00, spentMinor: 12279_00, remainingMinor: 1321_00, fraction: 0.9029)
    ),
    categoryCount: 4
  )
  .padding()
  .background(NomiColor.ground)
  .preferredColorScheme(.light)
}

#Preview("Left to spend · over budget") {
  RemainingBudgetCard(
    state: .remaining(
      BudgetTotals.Totals(budgetMinor: 18000_00, spentMinor: 18600_00, remainingMinor: -600_00, fraction: 1.033)
    ),
    categoryCount: 3
  )
  .padding()
  .background(NomiColor.ground)
  .preferredColorScheme(.light)
}

#Preview("Left to spend · prompt") {
  RemainingBudgetCard(state: .prompt)
    .padding()
    .background(NomiColor.ground)
    .preferredColorScheme(.light)
}

#Preview("Left to spend · accessibility 3") {
  RemainingBudgetCard(
    state: .remaining(
      BudgetTotals.Totals(budgetMinor: 13600_00, spentMinor: 12279_00, remainingMinor: 1321_00, fraction: 0.9029)
    ),
    categoryCount: 4
  )
  .padding()
  .background(NomiColor.ground)
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.light)
}
