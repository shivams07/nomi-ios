import NomiCore
import NomiPreview
import SwiftUI

/// The Accounts page (U11). Reads exclusively through `InsightsStore` (for
/// the read-only `AccountSummary` rollups) and `AccountStore` (for rename
/// and archive), same split as `DashboardView`/`AccountsCard` — this screen
/// has no opinion on how those summaries are computed, it just renders and
/// mutates through the two store protocols.
public struct AccountsScreen: View {
  public let accountStore: AccountStore
  public let insightsStore: InsightsStore

  @State private var renamingAccount: AccountSummary?
  @State private var archivingAccount: AccountSummary?
  @State private var isArchivedExpanded = false
  @State private var refreshToken = 0

  public init(accountStore: AccountStore, insightsStore: InsightsStore) {
    self.accountStore = accountStore
    self.insightsStore = insightsStore
  }

  private var summaries: [AccountSummary] {
    _ = refreshToken
    return (try? insightsStore.accountSummaries(includeArchived: true)) ?? []
  }

  private var active: [AccountSummary] { AccountSectioning.active(summaries) }
  private var archived: [AccountSummary] { AccountSectioning.archived(summaries) }

  public var body: some View {
    List {
      Section {
        if active.isEmpty {
          Text("No accounts yet")
            .nomiTextStyle(.caption)
            .foregroundStyle(NomiColor.textTertiary)
        } else {
          ForEach(active) { account in
            row(for: account, deemphasized: false)
          }
        }
      }
      if !archived.isEmpty {
        Section {
          DisclosureGroup("Archived (\(archived.count))", isExpanded: $isArchivedExpanded) {
            ForEach(archived) { account in
              row(for: account, deemphasized: true)
            }
          }
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.textTertiary)
        }
      }
    }
    .scrollContentBackground(.hidden)
    .background(NomiColor.surfaceCanvas)
    .navigationTitle("Accounts")
    .sheet(item: $renamingAccount) { account in
      AccountRenameSheet(accountStore: accountStore, account: account) {
        refreshToken += 1
      }
    }
    .alert(
      "Archive \(archivingAccount?.displayName ?? "account")?",
      isPresented: Binding(
        get: { archivingAccount != nil },
        set: { if !$0 { archivingAccount = nil } }
      ),
      presenting: archivingAccount,
      actions: { account in
        Button("Archive") {
          try? accountStore.setArchived(account.id, true)
          refreshToken += 1
        }
        Button("Cancel", role: .cancel) {}
      },
      message: { _ in
        Text("Transactions are kept. You can unarchive this account anytime.")
      }
    )
  }

  private func row(for account: AccountSummary, deemphasized: Bool) -> some View {
    HStack(alignment: .top, spacing: NomiSpacing.xs) {
      VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
        Text(account.displayName)
          .nomiTextStyle(.body)
          .foregroundStyle(deemphasized ? NomiColor.textQuaternary : NomiColor.textPrimary)
          .lineLimit(1)
        Text("\(account.institution) •• \(account.lastFour)")
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.textTertiary)
          .lineLimit(1)
        Text("\(account.transactionCount) transactions")
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.textTertiary)
      }
      Spacer(minLength: NomiSpacing.xs)
      VStack(alignment: .trailing, spacing: NomiSpacing.xxs) {
        Text("Tracked balance")
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.textTertiary)
        Text(TrackedBalanceText.string(minor: account.trackedBalanceMinor))
          .font(TabularFigures.font(name: NomiFont.montserratMedium, size: 16))
          .foregroundStyle(deemphasized ? NomiColor.textQuaternary : NomiColor.textPrimary)
        if let since = TrackedBalanceCaption.sinceText(account.trackingSince) {
          Text(since)
            .nomiTextStyle(.caption)
            .foregroundStyle(NomiColor.textTertiary)
        }
      }
    }
    .opacity(deemphasized ? 0.6 : 1)
    .listRowBackground(NomiColor.surfaceRaised)
    .contentShape(Rectangle())
    .onTapGesture { renamingAccount = account }
    .contextMenu {
      Button("Rename") { renamingAccount = account }
      if account.isArchived {
        Button("Unarchive") {
          try? accountStore.setArchived(account.id, false)
          refreshToken += 1
        }
      } else {
        Button("Archive") { archivingAccount = account }
      }
    }
  }
}

/// Explicit fixtures for the four cases the done-when requires a preview for:
/// positive tracked balance, negative, zero transactions, and archived.
/// Built directly rather than reused from `PreviewData` so each case is
/// unambiguous instead of incidental to whatever `PreviewData.transactions`
/// happens to sum to per account.
private enum AccountsScreenFixtures {
  static let positive = Account(id: UUID(), displayName: "HDFC •• 4471", institution: "HDFC Bank", lastFour: "4471", kindRaw: "bank", isArchived: false)
  static let negative = Account(id: UUID(), displayName: "ICICI •• 8890", institution: "ICICI Bank", lastFour: "8890", kindRaw: "bank", isArchived: false)
  static let zeroTransactions = Account(id: UUID(), displayName: "New Savings", institution: "HDFC Bank", lastFour: "9911", kindRaw: "bank", isArchived: false)
  static let archived = Account(id: UUID(), displayName: "Old Wallet", institution: "Paytm", lastFour: "0000", kindRaw: "wallet", isArchived: true)

  static let accounts: [Account] = [positive, negative, zeroTransactions, archived]

  static let transactions: [Transaction] = [
    Transaction(date: Date(timeIntervalSinceNow: -30 * 86400), amountMinor: 128_450_00, directionRaw: Direction.credit.rawValue, accountID: positive.id),
    Transaction(date: Date(timeIntervalSinceNow: -20 * 86400), amountMinor: 4_200_00, directionRaw: Direction.debit.rawValue, accountID: negative.id),
    Transaction(date: Date(timeIntervalSinceNow: -90 * 86400), amountMinor: 900_00, directionRaw: Direction.debit.rawValue, accountID: archived.id),
  ]
}

#Preview("Accounts — positive, negative, zero, and archived, dark") {
  NavigationStack {
    AccountsScreen(
      accountStore: FakeAccountStore(accounts: AccountsScreenFixtures.accounts),
      insightsStore: FakeInsightsStore(transactions: AccountsScreenFixtures.transactions, accounts: AccountsScreenFixtures.accounts)
    )
  }
  .preferredColorScheme(.dark)
}

#Preview("Accounts — none, dark") {
  NavigationStack {
    AccountsScreen(
      accountStore: FakeAccountStore(accounts: []),
      insightsStore: FakeInsightsStore(transactions: [], accounts: [])
    )
  }
  .preferredColorScheme(.dark)
}

#Preview("Accounts — accessibility 3, dark") {
  NavigationStack {
    AccountsScreen(
      accountStore: FakeAccountStore(accounts: AccountsScreenFixtures.accounts),
      insightsStore: FakeInsightsStore(transactions: AccountsScreenFixtures.transactions, accounts: AccountsScreenFixtures.accounts)
    )
  }
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.dark)
}
