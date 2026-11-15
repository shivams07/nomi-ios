import NomiCore
import NomiPreview
import SwiftUI

/// The "Assign it" destination (S8 step 5): the payments with no account, each row
/// opening the account picker. Choosing an account calls `setAccount` and reloads,
/// so a row that now has an account leaves the list.
struct UnassignedPaymentsScreen: View {
  let insightsStore: InsightsStore
  let transactionStore: TransactionStore
  let accountStore: AccountStore

  @State private var rows: [NomiCore.Transaction] = []
  @State private var loadFailed = false
  @State private var choosing: NomiCore.Transaction?
  @State private var errorMessage: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: NomiSpacing.cardGap) {
        if loadFailed {
          NomiLoadFailedCard { reload() }
        } else if rows.isEmpty {
          NomiEmptyState(
            systemImage: "checkmark.circle",
            title: "Every payment has an account",
            message: "Nothing here needs assigning. Balances are up to date."
          )
        } else {
          list
        }
        if let errorMessage {
          NomiStatusNote(errorMessage, tone: .error, systemImage: "exclamationmark.circle")
        }
      }
      .padding(.horizontal, NomiSpacing.screenGutter)
      .padding(.vertical, NomiSpacing.sm)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(NomiColor.ground)
    .navigationTitle(String(localized: "No account", bundle: .module))
    .task { reload() }
    .sheet(item: $choosing) { transaction in
      AccountPickerSheet(accountStore: accountStore, selection: nil) { accountID in
        assign(transaction, to: accountID)
      }
    }
  }

  private var list: some View {
    VStack(spacing: 0) {
      ForEach(rows) { transaction in
        Button {
          choosing = transaction
        } label: {
          TransactionRow(transaction: transaction, categoryName: nil, accountName: nil)
        }
        .buttonStyle(.plain)
      }
    }
    .nomiCard(padding: EdgeInsets())
  }

  private func reload() {
    do {
      rows = try insightsStore.unassignedTransactions()
      loadFailed = false
    } catch {
      rows = []
      loadFailed = true
    }
  }

  /// "Unassigned" in the picker keeps the payment as it is, so nothing is written.
  private func assign(_ transaction: NomiCore.Transaction, to accountID: UUID?) {
    choosing = nil
    guard let accountID else { return }
    do {
      try transactionStore.setAccount(transaction.id, to: accountID)
      errorMessage = nil
    } catch {
      errorMessage = "Could not assign this payment."
    }
    reload()
  }
}
