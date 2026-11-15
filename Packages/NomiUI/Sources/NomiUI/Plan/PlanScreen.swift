import NomiCore
import SwiftUI

/// The Plan tab (F3b, I-15). This is the stub F3b ships: its body is the budgets
/// list until S7 replaces it. The initializer is final, so S7 changes only the body.
public struct PlanScreen: View {
  public let budgetStore: BudgetStore
  public let insightsStore: InsightsStore
  public let recurringStore: (any RecurringInsightsStore)?
  @Binding public var notificationSettings: NotificationSettings
  public let isRequestingNotificationPermission: Bool
  public let refreshToken: Int

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
  }

  public var body: some View {
    BudgetsScreen(budgetStore: budgetStore, insightsStore: insightsStore, refreshToken: refreshToken)
  }
}
