import NomiCore
import NomiPreview
import SwiftUI

/// The Accounts page (U11). Reads exclusively through `InsightsStore` (for
/// the read-only `AccountSummary` rollups) and `AccountStore` (for edit,
/// archive, and delete), same split as `DashboardView`/`AccountsCard` — this
/// screen has no opinion on how those summaries are computed, it just renders
/// and mutates through the two store protocols.
public struct AccountsScreen: View {
  public let accountStore: AccountStore
  public let insightsStore: InsightsStore

  @State private var editingAccount: AccountSummary?
  @State private var archivingAccount: AccountSummary?
  @State private var deletingAccount: AccountSummary?
  @State private var isArchivedExpanded = false
  @State private var isCreatingAccount = false
  @State private var refreshToken = 0
  @State private var writeError = false

  public init(accountStore: AccountStore, insightsStore: InsightsStore) {
    self.accountStore = accountStore
    self.insightsStore = insightsStore
  }

  /// `nil` means the fetch threw — distinct from a legitimate empty account
  /// list, which is `[]` and renders the "No accounts yet" empty state.
  private var summaries: [AccountSummary]? {
    _ = refreshToken
    do {
      return try insightsStore.accountSummaries(includeArchived: true)
    } catch {
      return nil
    }
  }

  private var active: [AccountSummary] { AccountSectioning.active(summaries ?? []) }
  private var archived: [AccountSummary] { AccountSectioning.archived(summaries ?? []) }

  public var body: some View {
    List {
      Section {
        if summaries == nil {
          Text("Couldn't load accounts")
            .nomiTextStyle(.caption)
            .foregroundStyle(NomiColor.textTertiary)
        } else if active.isEmpty {
          VStack(alignment: .leading, spacing: NomiSpacing.xs) {
            Text("No accounts yet")
              .nomiTextStyle(.caption)
              .foregroundStyle(NomiColor.textTertiary)
            Text("Create your first account to start tracking balances and assigning transactions.")
              .nomiTextStyle(.caption)
              .foregroundStyle(NomiColor.textTertiary)
            Button {
              isCreatingAccount = true
            } label: {
              Label("New Account", systemImage: "plus")
                .foregroundStyle(NomiColor.accent)
            }
          }
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
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          isCreatingAccount = true
        } label: {
          Image(systemName: "plus")
        }
      }
    }
    .sheet(item: $editingAccount) { account in
      AccountRenameSheet(accountStore: accountStore, account: account) {
        refreshToken += 1
      }
    }
    .sheet(isPresented: $isCreatingAccount) {
      AccountCreateSheet(accountStore: accountStore) { _ in
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
          do {
            try accountStore.setArchived(account.id, true)
            refreshToken += 1
          } catch {
            writeError = true
          }
        }
        Button("Cancel", role: .cancel) {}
      },
      message: { _ in
        Text("Transactions are kept. You can unarchive this account anytime.")
      }
    )
    .confirmationDialog(
      "Delete \(deletingAccount?.displayName ?? "account")?",
      isPresented: Binding(
        get: { deletingAccount != nil },
        set: { if !$0 { deletingAccount = nil } }
      ),
      titleVisibility: .visible,
      presenting: deletingAccount,
      actions: { account in
        Button("Delete", role: .destructive) {
          do {
            try accountStore.delete(account.id)
            refreshToken += 1
          } catch {
            writeError = true
          }
        }
        Button("Cancel", role: .cancel) {}
      },
      message: { account in
        Text(AccountDeleteConfirmation.message(transactionCount: account.transactionCount))
      }
    )
    .alert("Couldn't complete that", isPresented: $writeError) {
      Button("OK", role: .cancel) {}
    }
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
    .onTapGesture { editingAccount = account }
    .contextMenu {
      Button("Edit") { editingAccount = account }
      if account.isArchived {
        Button("Unarchive") {
          do {
            try accountStore.setArchived(account.id, false)
            refreshToken += 1
          } catch {
            writeError = true
          }
        }
      } else {
        Button("Archive") { archivingAccount = account }
      }
      Button("Delete", role: .destructive) { deletingAccount = account }
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

  static let transactions: [NomiCore.Transaction] = [
    NomiCore.Transaction(date: Date(timeIntervalSinceNow: -30 * 86400), amountMinor: 128_450_00, directionRaw: Direction.credit.rawValue, accountID: positive.id),
    NomiCore.Transaction(date: Date(timeIntervalSinceNow: -20 * 86400), amountMinor: 4_200_00, directionRaw: Direction.debit.rawValue, accountID: negative.id),
    NomiCore.Transaction(date: Date(timeIntervalSinceNow: -90 * 86400), amountMinor: 900_00, directionRaw: Direction.debit.rawValue, accountID: archived.id),
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

private struct AccountsScreenLoadFailure: Error {}

/// Only `accountSummaries` throws — this screen never calls the other
/// `InsightsStore` methods, so they can return empty rather than also throw.
@MainActor
private final class FailingAccountSummariesStore: InsightsStore {
  func insights(for period: InsightPeriod) throws -> PeriodInsights { throw AccountsScreenLoadFailure() }
  func trend(months: Int) throws -> [MonthBucket] { [] }
  func accountSummaries(includeArchived: Bool) throws -> [AccountSummary] { throw AccountsScreenLoadFailure() }
  func budgetProgress(year: Int, month: Int) throws -> [BudgetProgress] { [] }
  func transactions(in period: InsightPeriod) throws -> [NomiCore.Transaction] { [] }
}

#Preview("Accounts — failed to load, dark") {
  NavigationStack {
    AccountsScreen(
      accountStore: FakeAccountStore(accounts: []),
      insightsStore: FailingAccountSummariesStore()
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

/// Isolated confirmationDialog preview, `CategoriesScreen`'s
/// `.constant(true)` pattern — names a transaction count so the message
/// (`AccountDeleteConfirmation`) is checkable without navigating the full
/// screen and tapping through a context menu.
#Preview("Accounts — delete confirmation, dark") {
  Text("HDFC •• 4471")
    .nomiTextStyle(.body)
    .foregroundStyle(NomiColor.textPrimary)
    .padding()
    .background(NomiColor.surfaceRow)
    .confirmationDialog("Delete HDFC •• 4471?", isPresented: .constant(true), titleVisibility: .visible) {
      Button("Delete", role: .destructive) {}
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(AccountDeleteConfirmation.message(transactionCount: 42))
    }
    .background(NomiColor.surfaceCanvas)
    .preferredColorScheme(.dark)
}
