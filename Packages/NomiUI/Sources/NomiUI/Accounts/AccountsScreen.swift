import NomiCore
import NomiPreview
import SwiftUI

/// The Accounts page (U11, AC). Reads exclusively through `InsightsStore` (for
/// the read-only `AccountSummary` rollups) and `AccountStore` (for edit,
/// archive, and delete), same split as `DashboardView`/`AccountsCard`. This
/// screen has no opinion on how those summaries are computed.
///
/// Shape, from the approved `Cards` artboard: a nav row with the title only,
/// the hero with "Tracked balance" and the total, then the sheet. The sheet
/// holds "All accounts" and one card of 72 pt rows (tap edits, long-press
/// keeps its menu), the "Add account" footer row, and a collapsed "Archived"
/// disclosure. The sheet and hero come from `NomiHeroScaffold`.
public struct AccountsScreen: View {
  public let accountStore: AccountStore
  public let insightsStore: InsightsStore

  @State private var editingAccount: AccountSummary?
  @State private var archivingAccount: AccountSummary?
  @State private var deletingAccount: AccountSummary?
  /// Set by the edit sheet's Archive or Delete. Presented once the sheet has
  /// gone (`presentPendingEditAction`), so no alert appears over a sheet that
  /// is still dismissing.
  @State private var pendingEditAction: PendingEditAction?
  @State private var isArchivedExpanded = false
  @State private var isCreatingAccount = false
  @State private var refreshToken = 0
  @State private var writeError = false

  private enum PendingEditAction {
    case archive(AccountSummary)
    case delete(AccountSummary)
  }

  public init(accountStore: AccountStore, insightsStore: InsightsStore) {
    self.accountStore = accountStore
    self.insightsStore = insightsStore
  }

  /// `nil` means the fetch threw, distinct from a legitimate empty account
  /// list, which is `[]` and renders the "No accounts yet" empty state.
  private var summaries: [AccountSummary]? {
    _ = refreshToken
    do {
      return try insightsStore.accountSummaries(includeArchived: true)
    } catch {
      return nil
    }
  }

  /// The hero total of a loaded read, or nil when the read failed. A failed
  /// read shows no number rather than ₹0.00, because a wrong total must not
  /// look right.
  private static func total(of loaded: [AccountSummary]?) -> Int? {
    guard let loaded else { return nil }
    return AccountBalanceDisplay.total(
      loaded.map { (isArchived: $0.isArchived, trackedMinor: $0.trackedBalanceMinor) }
    )
  }

  public var body: some View {
    // One read per render: the hero and the sheet both draw from this snapshot.
    let loaded = summaries
    return NomiHeroScaffold(heroBottomSpacing: 40) {
      navRow
    } hero: {
      heroBlock(loaded)
    } sheet: {
      sheetBlock(loaded)
    }
    .sheet(item: $editingAccount, onDismiss: { presentPendingEditAction() }) { account in
      AccountRenameSheet(
        accountStore: accountStore,
        account: account,
        onSaved: { refreshToken += 1 },
        onArchive: { pendingEditAction = .archive(account) },
        onDelete: { pendingEditAction = .delete(account) }
      )
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
        Button("Archive") { archiveAccount(account) }
        Button("Cancel", role: .cancel) {}
      },
      message: { _ in
        Text(AccountBalanceDisplay.archiveMessage)
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
        Button("Archive instead") { archiveAccount(account) }
        Button("Delete", role: .destructive) { deleteAccount(account) }
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

  // MARK: - Hero

  private var navRow: some View {
    Text("Accounts")
      .nomiTextStyle(.heroTitle)
      .foregroundStyle(NomiColor.heroText)
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityAddTraits(.isHeader)
  }

  /// No chip: the approved artboard draws none (SIMP Q7 = B).
  private func heroBlock(_ loaded: [AccountSummary]?) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("Tracked balance")
        .nomiTextStyle(.subhead)
        .foregroundStyle(NomiColor.heroTextSecondary)
      if let total = Self.total(of: loaded) {
        NomiAmountText(minor: total, context: .hero, style: .heroAmount)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: - Sheet

  @ViewBuilder
  private func sheetBlock(_ loaded: [AccountSummary]?) -> some View {
    let active = AccountSectioning.active(loaded ?? [])
    let archived = AccountSectioning.archived(loaded ?? [])
    if loaded == nil {
      NomiLoadFailedCard(message: "Accounts and balances aren’t available right now.") {
        refreshToken += 1
      }
      addAccountRow
    } else if active.isEmpty && archived.isEmpty {
      NomiEmptyState(
        systemImage: "creditcard",
        title: "No accounts yet",
        message: "Add an account to see a tracked balance.",
        actionTitle: "Add account"
      ) {
        isCreatingAccount = true
      }
    } else {
      VStack(alignment: .leading, spacing: NomiSpacing.cardGap) {
        Text("All accounts")
          .nomiTextStyle(.headline)
          .foregroundStyle(NomiColor.ink)
          .accessibilityAddTraits(.isHeader)
        if !active.isEmpty {
          accountList(active, deemphasized: false)
        }
        addAccountRow
        if !archived.isEmpty {
          archivedSection(archived)
        }
      }
    }
  }

  private func accountList(_ accounts: [AccountSummary], deemphasized: Bool) -> some View {
    VStack(spacing: 0) {
      ForEach(accounts) { account in
        accountRow(account, showsDivider: account.id != accounts.last?.id, deemphasized: deemphasized)
      }
    }
    .nomiCard(padding: EdgeInsets())
  }

  /// One 72 pt row. Tapping opens the edit sheet, where Archive and Delete
  /// now live. The long-press menu keeps its own actions.
  private func accountRow(_ account: AccountSummary, showsDivider: Bool, deemphasized: Bool) -> some View {
    let kind = AccountKindOptions.kind(raw: account.kindRaw)
    let amount = AccountBalanceDisplay.line(kind: kind, trackedMinor: account.trackedBalanceMinor)
    let caption = AccountBalanceDisplay.rowCaption(
      kind: kind,
      trackedMinor: account.trackedBalanceMinor,
      openingMinor: account.openingBalanceMinor
    )
    return Button {
      editingAccount = account
    } label: {
      HStack(alignment: .center, spacing: NomiSpacing.cardGap) {
        AccountTile(symbolName: AccountTileSymbol.name(for: kind))
        VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
          Text(account.displayName)
            .nomiTextStyle(.rowTitle)
            .foregroundStyle(NomiColor.ink)
            .lineLimit(1)
          Text(AccountRowText.subtitle(
            institution: account.institution,
            lastFour: account.lastFour,
            transactionCount: account.transactionCount
          ))
            .nomiTextStyle(.footnote)
            .foregroundStyle(NomiColor.inkSecondary)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        VStack(alignment: .trailing, spacing: 2) {
          NomiAmountText(minor: amount.minor, style: .amount)
          if let caption {
            Text(caption)
              .nomiTextStyle(.micro)
              .foregroundStyle(NomiColor.inkSecondary)
          }
        }
        .layoutPriority(1)
      }
      .padding(.horizontal, NomiSpacing.sm)
      .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
      .contentShape(Rectangle())
      .overlay(alignment: .bottom) {
        if showsDivider {
          Rectangle()
            .fill(NomiColor.separator)
            .frame(height: 1)
        }
      }
    }
    .buttonStyle(.plain)
    .opacity(deemphasized ? 0.6 : 1)
    .contextMenu {
      Button("Edit") { editingAccount = account }
      if account.isArchived {
        Button("Unarchive") { unarchiveAccount(account) }
      } else {
        Button("Archive") { archivingAccount = account }
      }
      Button("Delete", role: .destructive) { deletingAccount = account }
    }
  }

  /// The footer row that replaces the hero "+" (SIMP §3 item 4).
  private var addAccountRow: some View {
    Button {
      isCreatingAccount = true
    } label: {
      HStack(spacing: NomiSpacing.xs) {
        Image(systemName: "plus")
          .resizable()
          .scaledToFit()
          .frame(width: 20, height: 20)
        Text("Add account")
          .nomiTextStyle(.body)
        Spacer(minLength: 0)
      }
      .foregroundStyle(NomiColor.navy)
      .padding(.horizontal, NomiSpacing.sm)
      .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
      .nomiCard(padding: EdgeInsets())
    }
    .buttonStyle(.plain)
  }

  private func archivedSection(_ archived: [AccountSummary]) -> some View {
    DisclosureGroup(isExpanded: $isArchivedExpanded) {
      accountList(archived, deemphasized: true)
    } label: {
      Text("Archived")
    }
    .disclosureGroupStyle(TrailingChevronDisclosureStyle())
  }

  // MARK: - Actions

  /// Runs the Archive or Delete the edit sheet asked for, now that the sheet
  /// has gone, so the existing confirmation presents on a clear screen.
  private func presentPendingEditAction() {
    guard let action = pendingEditAction else { return }
    pendingEditAction = nil
    switch action {
    case .archive(let account):
      archivingAccount = account
    case .delete(let account):
      deletingAccount = account
    }
  }

  private func archiveAccount(_ account: AccountSummary) {
    do {
      try accountStore.setArchived(account.id, true)
      refreshToken += 1
    } catch {
      writeError = true
    }
  }

  private func unarchiveAccount(_ account: AccountSummary) {
    do {
      try accountStore.setArchived(account.id, false)
      refreshToken += 1
    } catch {
      writeError = true
    }
  }

  private func deleteAccount(_ account: AccountSummary) {
    do {
      try accountStore.delete(account.id)
      refreshToken += 1
    } catch {
      writeError = true
    }
  }
}

/// The 40 pt icon tile at the start of an account row: an `iconGlyph` symbol
/// on an `iconTile` circle, the neutral badge from the approved artboards.
private struct AccountTile: View {
  let symbolName: String

  var body: some View {
    Image(systemName: symbolName)
      .resizable()
      .scaledToFit()
      .frame(width: 20, height: 20)
      .foregroundStyle(NomiColor.iconGlyph)
      .frame(width: 40, height: 40)
      .background(Circle().fill(NomiColor.iconTile))
      .accessibilityHidden(true)
  }
}

/// A disclosure with its chevron on the trailing edge and the header in ink,
/// collapsed by default (the Accounts artboard). The header is a button, and
/// its value says whether it is expanded.
private struct TrailingChevronDisclosureStyle: DisclosureGroupStyle {
  func makeBody(configuration: Configuration) -> some View {
    VStack(alignment: .leading, spacing: NomiSpacing.cardGap) {
      Button {
        withAnimation(.easeInOut(duration: 0.2)) {
          configuration.isExpanded.toggle()
        }
      } label: {
        HStack(spacing: NomiSpacing.xs) {
          configuration.label
          Spacer(minLength: 0)
          Image(systemName: "chevron.down")
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
            .rotationEffect(.degrees(configuration.isExpanded ? 180 : 0))
        }
        .nomiTextStyle(.rowTitle)
        .foregroundStyle(NomiColor.inkDeep)
        .frame(maxWidth: .infinity, minHeight: NomiSpacing.minTarget, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")

      if configuration.isExpanded {
        configuration.content
      }
    }
  }
}

/// Explicit fixtures for the cases the done-when requires a preview for:
/// a positive bank balance with an opening balance, a card owed, zero
/// transactions, and archived.
private enum AccountsScreenFixtures {
  static let positive = Account(id: UUID(), displayName: "HDFC Savings", institution: "HDFC Bank", lastFour: "4471", kindRaw: "bank", isArchived: false, openingBalanceMinor: 1_20_000_00)
  static let owed = Account(id: UUID(), displayName: "ICICI Credit Card", institution: "ICICI Bank", lastFour: "9012", kindRaw: "card", isArchived: false)
  static let zeroTransactions = Account(id: UUID(), displayName: "New Savings", institution: "HDFC Bank", lastFour: "9911", kindRaw: "bank", isArchived: false)
  static let archived = Account(id: UUID(), displayName: "Old Wallet", institution: "Paytm", lastFour: "", kindRaw: "wallet", isArchived: true)

  static let accounts: [Account] = [positive, owed, zeroTransactions, archived]

  static let transactions: [NomiCore.Transaction] = [
    NomiCore.Transaction(date: Date(timeIntervalSinceNow: -30 * 86400), amountMinor: 128_450_00, directionRaw: Direction.credit.rawValue, accountID: positive.id),
    NomiCore.Transaction(date: Date(timeIntervalSinceNow: -20 * 86400), amountMinor: 18_420_50, directionRaw: Direction.debit.rawValue, accountID: owed.id),
    NomiCore.Transaction(date: Date(timeIntervalSinceNow: -90 * 86400), amountMinor: 900_00, directionRaw: Direction.debit.rawValue, accountID: archived.id),
  ]
}

#Preview("Accounts — bank, owed card, zero, and archived, light") {
  NavigationStack {
    AccountsScreen(
      accountStore: FakeAccountStore(accounts: AccountsScreenFixtures.accounts),
      insightsStore: FakeInsightsStore(transactions: AccountsScreenFixtures.transactions, accounts: AccountsScreenFixtures.accounts)
    )
  }
  .preferredColorScheme(.light)
}

#Preview("Accounts — none, light") {
  NavigationStack {
    AccountsScreen(
      accountStore: FakeAccountStore(accounts: []),
      insightsStore: FakeInsightsStore(transactions: [], accounts: [])
    )
  }
  .preferredColorScheme(.light)
}

private struct AccountsScreenLoadFailure: Error {}

/// Only `accountSummaries` throws. This screen never calls the other
/// `InsightsStore` methods, so they can return empty rather than also throw.
@MainActor
private final class FailingAccountSummariesStore: InsightsStore {
  func insights(for period: InsightPeriod) throws -> PeriodInsights { throw AccountsScreenLoadFailure() }
  func trend(months: Int) throws -> [MonthBucket] { [] }
  func accountSummaries(includeArchived: Bool) throws -> [AccountSummary] { throw AccountsScreenLoadFailure() }
  func budgetProgress(year: Int, month: Int) throws -> [BudgetProgress] { [] }
  func transactions(in period: InsightPeriod) throws -> [NomiCore.Transaction] { [] }
}

#Preview("Accounts — failed to load, light") {
  NavigationStack {
    AccountsScreen(
      accountStore: FakeAccountStore(accounts: []),
      insightsStore: FailingAccountSummariesStore()
    )
  }
  .preferredColorScheme(.light)
}

#Preview("Accounts — accessibility 3, light") {
  NavigationStack {
    AccountsScreen(
      accountStore: FakeAccountStore(accounts: AccountsScreenFixtures.accounts),
      insightsStore: FakeInsightsStore(transactions: AccountsScreenFixtures.transactions, accounts: AccountsScreenFixtures.accounts)
    )
  }
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.light)
}

/// Isolated confirmationDialog preview, `CategoriesScreen`'s `.constant(true)`
/// pattern. It names a transaction count so the message
/// (`AccountDeleteConfirmation`) is checkable without navigating the full
/// screen and tapping through a context menu.
#Preview("Accounts — delete confirmation, light") {
  Text("ICICI Credit Card")
    .nomiTextStyle(.body)
    .foregroundStyle(NomiColor.ink)
    .padding()
    .background(NomiColor.card)
    .confirmationDialog("Delete ICICI Credit Card?", isPresented: .constant(true), titleVisibility: .visible) {
      Button("Archive instead") {}
      Button("Delete", role: .destructive) {}
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(AccountDeleteConfirmation.message(transactionCount: 42))
    }
    .background(NomiColor.ground)
    .preferredColorScheme(.light)
}
