import NomiCore
import SwiftUI

/// The Review queue (F3b, I-15). This is the stub F3b ships: a placeholder with a
/// Close button until S4 replaces the body. The initializer is final.
public struct ReviewQueueScreen: View {
  public let transactionStore: TransactionStore
  public let insightsStore: InsightsStore
  public let categoryStore: CategoryStore
  public let ruleStore: RuleStore
  public let accountStore: AccountStore
  public let editor: TransactionEditing
  public let suggester: (any CategorySuggesting)?
  public let onClose: () -> Void

  public init(
    transactionStore: TransactionStore,
    insightsStore: InsightsStore,
    categoryStore: CategoryStore,
    ruleStore: RuleStore,
    accountStore: AccountStore,
    editor: TransactionEditing,
    suggester: (any CategorySuggesting)?,
    onClose: @escaping () -> Void
  ) {
    self.transactionStore = transactionStore
    self.insightsStore = insightsStore
    self.categoryStore = categoryStore
    self.ruleStore = ruleStore
    self.accountStore = accountStore
    self.editor = editor
    self.suggester = suggester
    self.onClose = onClose
  }

  public var body: some View {
    NomiEmptyState(
      systemImage: "checkmark.circle",
      title: "Review",
      message: "Coming in the next update.",
      actionTitle: "Close",
      action: onClose
    )
  }
}
