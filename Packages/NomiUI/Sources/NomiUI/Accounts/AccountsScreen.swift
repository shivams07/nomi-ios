import NomiCore
import NomiPreview
import SwiftUI

/// The Accounts page (S8, from the Accounts artboard). Pushed from Settings › Organize.
/// The system navigation bar is kept, so its back control is always there, at every
/// text size (S8 must-fix). It carries the large title "Accounts" and the "Add account"
/// pill. The body is the "Estimated balance" header over the total, one physical card
/// per active account, the unassigned note, and the Archived disclosure.
///
/// The reads go through `AccountsModel`, which reads `InsightsStore` for the summaries
/// and the unassigned count. Writes go through `AccountStore`, the same split as before.
public struct AccountsScreen: View {
  public let accountStore: AccountStore
  public let insightsStore: InsightsStore

  /// G4. The composition root's `InsightsCache` generation. A new value from the parent
  /// reloads the summaries, the same contract as `DashboardView.refreshToken`. This
  /// screen's own writes bump `writeToken` instead.
  public let refreshToken: Int

  /// S8 step 5. Opens the unassigned note's "Assign it". `nil` shows the note without
  /// its action. RootView passes it through S9a (or X1).
  public let transactionStore: TransactionStore?

  @State private var model: AccountsModel
  @State private var editingAccount: AccountSummary?
  @State private var archivingAccount: AccountSummary?
  @State private var deletingAccount: AccountSummary?
  /// Set by the edit sheet's Archive or Delete. Presented once the sheet has gone
  /// (`presentPendingEditAction`), so no alert appears over a sheet that is still dismissing.
  @State private var pendingEditAction: PendingEditAction?
  @State private var isArchivedExpanded = false
  @State private var isCreatingAccount = false
  @State private var isShowingUnassigned = false
  /// Bumped by this screen's own writes, so the summaries re-read after a rename,
  /// archive, delete or create.
  @State private var writeToken = 0
  @State private var writeError = false

  private enum PendingEditAction {
    case archive(AccountSummary)
    case delete(AccountSummary)
  }

  /// What the read depends on. Either input changing reloads the screen.
  private struct LoadKey: Equatable {
    let refresh: Int
    let writes: Int
  }

  public init(
    accountStore: AccountStore,
    insightsStore: InsightsStore,
    refreshToken: Int = 0,
    transactionStore: TransactionStore? = nil
  ) {
    self.accountStore = accountStore
    self.insightsStore = insightsStore
    self.refreshToken = refreshToken
    self.transactionStore = transactionStore
    _model = State(initialValue: AccountsModel(insightsStore: insightsStore))
  }

  public var body: some View {
    ScrollView {
      content
        .padding(.horizontal, NomiSpacing.screenGutter)
        .padding(.vertical, NomiSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(NomiColor.ground.ignoresSafeArea())
    .navigationTitle(String(localized: "Accounts", bundle: .module))
    #if os(iOS)
    .navigationBarTitleDisplayMode(.large)
    #endif
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        addAccountButton
      }
    }
    .task(id: LoadKey(refresh: refreshToken, writes: writeToken)) {
      model.load()
    }
    .onChange(of: isShowingUnassigned) { _, showing in
      // Coming back from the assign screen: the unassigned count may have changed.
      if !showing { model.load() }
    }
    .navigationDestination(isPresented: $isShowingUnassigned) {
      if let transactionStore {
        UnassignedPaymentsScreen(
          insightsStore: insightsStore,
          transactionStore: transactionStore,
          accountStore: accountStore
        )
      }
    }
    .sheet(item: $editingAccount, onDismiss: { presentPendingEditAction() }) { account in
      AccountRenameSheet(
        accountStore: accountStore,
        account: account,
        onSaved: { writeToken += 1 },
        onArchive: { pendingEditAction = .archive(account) },
        onDelete: { pendingEditAction = .delete(account) }
      )
    }
    .sheet(isPresented: $isCreatingAccount) {
      AccountCreateSheet(accountStore: accountStore) { _ in
        writeToken += 1
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
    .alert(
      "Delete \(deletingAccount?.displayName ?? "account")?",
      isPresented: Binding(
        get: { deletingAccount != nil },
        set: { if !$0 { deletingAccount = nil } }
      ),
      presenting: deletingAccount,
      actions: { account in
        Button("Archive instead") { routeDeleteChoice(.archiveInstead, for: account) }
        Button("Delete", role: .destructive) { routeDeleteChoice(.delete, for: account) }
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

  // MARK: - Body

  /// The page follows the read's state: a skeleton while loading, a load-failed card
  /// when the read threw, the empty state when there are no accounts, and otherwise
  /// the header, the cards, the note and the archived section.
  @ViewBuilder
  private var content: some View {
    switch model.state {
    case .loading:
      NomiSkeleton(lines: [0.4, 0.62, 1])
    case .failed:
      NomiLoadFailedCard(message: "Accounts and balances aren’t available right now.") {
        model.load()
      }
    case .loaded:
      if model.active.isEmpty && model.archived.isEmpty {
        NomiEmptyState(
          systemImage: "creditcard",
          title: "No accounts yet",
          message: "Add the accounts your alerts mention, so each payment lands in the right place.",
          actionTitle: "Add account"
        ) {
          isCreatingAccount = true
        }
      } else {
        VStack(alignment: .leading, spacing: NomiSpacing.cardGap) {
          if !model.active.isEmpty {
            header
            cards
          }
          unassignedNote
          if !model.archived.isEmpty {
            archivedSection
          }
        }
      }
    }
  }

  /// The label over the total, then the total at 38 pt. Hidden when only archived
  /// accounts remain, since the total then covers nothing.
  private var header: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(AccountsHeader.line(trackedSince: model.trackingSince))
        .nomiTextStyle(.subhead)
        .foregroundStyle(NomiColor.inkSecondary)
        .accessibilityAddTraits(.isHeader)
      AccountAmountLabel(minor: model.totalMinor, size: 38, color: NomiColor.ink)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var cards: some View {
    VStack(spacing: NomiSpacing.cardGap) {
      ForEach(model.active) { account in
        AccountCard(account: account) {
          editingAccount = account
        }
        .contextMenu { accountMenu(for: account) }
      }
    }
  }

  /// "1 payment has no account" with its action when the screen can offer one.
  @ViewBuilder
  private var unassignedNote: some View {
    if let note = UnassignedNote.text(count: model.unassignedCount) {
      if transactionStore != nil {
        NomiStatusNote(
          note,
          tone: .warning,
          systemImage: "exclamationmark.circle",
          actionTitle: String(localized: "Assign it", bundle: .module)
        ) {
          isShowingUnassigned = true
        }
      } else {
        NomiStatusNote(note, tone: .warning, systemImage: "exclamationmark.circle")
      }
    }
  }

  private var archivedSection: some View {
    DisclosureGroup(isExpanded: $isArchivedExpanded) {
      accountList(model.archived)
    } label: {
      Text("Archived")
    }
    .disclosureGroupStyle(TrailingChevronDisclosureStyle())
  }

  /// Archived accounts as plain rows, de-emphasised. They are not in the total.
  private func accountList(_ accounts: [AccountSummary]) -> some View {
    VStack(spacing: 0) {
      ForEach(accounts) { account in
        archivedRow(account, showsDivider: account.id != accounts.last?.id)
      }
    }
    .nomiCard(padding: EdgeInsets())
  }

  private func archivedRow(_ account: AccountSummary, showsDivider: Bool) -> some View {
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
          Text(AccountRowText.subtitle(
            institution: account.institution,
            lastFour: account.lastFour,
            transactionCount: account.transactionCount
          ))
            .nomiTextStyle(.footnote)
            .foregroundStyle(NomiColor.inkSecondary)
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
    .opacity(0.6)
    .contextMenu { accountMenu(for: account) }
  }

  /// The long-press menu on a card or an archived row. Archive and Delete ask first.
  @ViewBuilder
  private func accountMenu(for account: AccountSummary) -> some View {
    Button("Edit") { editingAccount = account }
    if account.isArchived {
      Button("Unarchive") { unarchiveAccount(account) }
    } else {
      Button("Archive") { archivingAccount = account }
    }
    Button("Delete", role: .destructive) { deletingAccount = account }
  }

  /// The toolbar's small primary pill.
  private var addAccountButton: some View {
    Button {
      isCreatingAccount = true
    } label: {
      Label(String(localized: "Add account", bundle: .module), systemImage: "plus")
    }
    .buttonStyle(.borderedProminent)
    .buttonBorderShape(.capsule)
    .controlSize(.small)
    .tint(NomiColor.navy)
  }

  // MARK: - Actions

  /// Runs the Archive or Delete the edit sheet asked for, now that the sheet has gone,
  /// so the existing confirmation presents on a clear screen.
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

  /// Carries out a delete-dialog choice. "Archive instead" hands the account to the
  /// archive alert and does not archive here, so the DEC-06 sentence is always shown
  /// before the Estimated balance moves.
  private func routeDeleteChoice(_ choice: AccountDeleteChoice, for account: AccountSummary) {
    switch AccountDeleteRouting.outcome(for: choice) {
    case .presentArchiveAlert:
      deletingAccount = nil
      archivingAccount = account
    case .deleteAccount:
      deleteAccount(account)
    }
  }

  private func archiveAccount(_ account: AccountSummary) {
    do {
      try accountStore.setArchived(account.id, true)
      writeToken += 1
    } catch {
      writeError = true
    }
  }

  private func unarchiveAccount(_ account: AccountSummary) {
    do {
      try accountStore.setArchived(account.id, false)
      writeToken += 1
    } catch {
      writeError = true
    }
  }

  private func deleteAccount(_ account: AccountSummary) {
    do {
      try accountStore.delete(account.id)
      writeToken += 1
    } catch {
      writeError = true
    }
  }
}

/// Manual conformance, as on `DashboardView`: the stores are `AnyObject` protocols, so
/// identity stands in for equality, and `refreshToken` is compared so a test can assert
/// that a new generation makes a different view value.
extension AccountsScreen: Equatable {
  public static func == (lhs: AccountsScreen, rhs: AccountsScreen) -> Bool {
    lhs.accountStore === rhs.accountStore
      && lhs.insightsStore === rhs.insightsStore
      && lhs.transactionStore === rhs.transactionStore
      && lhs.refreshToken == rhs.refreshToken
  }
}

/// The 40 pt icon tile on an archived row and on a wallet card: an `iconGlyph` symbol on
/// an `iconTile` circle, the neutral badge from the approved artboards.
struct AccountTile: View {
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

/// A disclosure with its chevron on the trailing edge and the header in ink, collapsed
/// by default (the Accounts artboard). The header is a button, and its value says whether
/// it is expanded.
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

/// Explicit fixtures for the cases the done-when requires a preview for: a positive bank
/// balance with an opening balance, a card owed, zero transactions, and archived.
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

/// Only `accountSummaries` throws. This screen never calls the other `InsightsStore`
/// methods, so they can return empty rather than also throw.
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

/// Isolated confirmationDialog preview, `CategoriesScreen`'s `.constant(true)` pattern. It
/// names a transaction count so the message (`AccountDeleteConfirmation`) is checkable
/// without navigating the full screen and tapping through a context menu.
#Preview("Accounts — delete confirmation, light") {
  Text("ICICI Credit Card")
    .nomiTextStyle(.body)
    .foregroundStyle(NomiColor.ink)
    .padding()
    .background(NomiColor.card)
    .alert("Delete ICICI Credit Card?", isPresented: .constant(true)) {
      Button("Archive instead") {}
      Button("Delete", role: .destructive) {}
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(AccountDeleteConfirmation.message(transactionCount: 42))
    }
    .background(NomiColor.ground)
    .preferredColorScheme(.light)
}
