import NomiCore
import NomiPreview
import SwiftUI
import UserNotifications

/// The Settings screen (U7, v5 addition; restyled to the Settings artboard by
/// ST). Five groups, top to bottom: Mail account (address and status, one
/// "Scan mail" menu, Manage connection, Not matched), Organize (Categories,
/// Budgets when its stores are passed, Rules), Data (Import from file, and
/// iCloud sync as a read-only value), Preferences (the budget-alert switch),
/// and About. Reads `Design/**`. Must not edit it.
public struct SettingsScreen: View {
  public let mailConnectionService: MailConnectionService
  public let fileImportService: FileImportService
  public let categoryStore: CategoryStore
  public let ruleStore: RuleStore
  @Binding public var notificationSettings: NotificationSettings
  public let storageMode: StorageMode
  /// The live account list, passed through to `RulesScreen` so the rule
  /// editor's Account picker has something to show. `RootView` supplies it;
  /// the default `[]` keeps every preview compiling and leaves the picker at
  /// "Any", which is what an empty list shows anyway.
  public let accounts: [NomiCore.Account]
  /// The Budgets row (ST). It appears under Organize only when both stores
  /// are passed, so every call site that does not pass them compiles and shows
  /// no row. The toolbar icon this replaces is `RootView`'s to remove (S1).
  public let budgetStore: BudgetStore?
  public let insightsStore: InsightsStore?
  /// G4. Passed on to the Budgets row, so a pushed `BudgetsScreen` re-reads
  /// when the cache is invalidated. Stored and never read here, as on
  /// `DashboardView.refreshToken`.
  public let refreshToken: Int

  @State private var connectionState: MailConnectionState = .disconnected
  @State private var permissionDenied = false
  @State private var isRescanning = false
  @State private var isScanningRecent = false
  @State private var lastSyncSummary: SyncSummary?
  @State private var rescanError: String?
  private let forcedPermissionDenied: Bool?

  @Environment(\.scenePhase) private var scenePhase

  /// `storageMode` defaults to `.cloudKit` so every existing call site and
  /// preview compiles unchanged; `RootView` passes the real value.
  public init(
    mailConnectionService: MailConnectionService,
    fileImportService: FileImportService,
    categoryStore: CategoryStore,
    ruleStore: RuleStore,
    notificationSettings: Binding<NotificationSettings>,
    storageMode: StorageMode = .cloudKit,
    accounts: [NomiCore.Account] = [],
    budgetStore: BudgetStore? = nil,
    insightsStore: InsightsStore? = nil,
    refreshToken: Int = 0
  ) {
    self.mailConnectionService = mailConnectionService
    self.fileImportService = fileImportService
    self.categoryStore = categoryStore
    self.ruleStore = ruleStore
    _notificationSettings = notificationSettings
    self.storageMode = storageMode
    self.accounts = accounts
    self.budgetStore = budgetStore
    self.insightsStore = insightsStore
    self.refreshToken = refreshToken
    forcedPermissionDenied = nil
  }

  /// Preview/test-only entry point — forces the permission-denied state
  /// rather than depending on the canvas machine's live notification
  /// authorization, which cannot be relied on to be "denied" on demand.
  init(
    mailConnectionService: MailConnectionService,
    fileImportService: FileImportService,
    categoryStore: CategoryStore,
    ruleStore: RuleStore,
    notificationSettings: Binding<NotificationSettings>,
    forcedPermissionDenied: Bool,
    storageMode: StorageMode = .cloudKit,
    accounts: [NomiCore.Account] = [],
    budgetStore: BudgetStore? = nil,
    insightsStore: InsightsStore? = nil,
    refreshToken: Int = 0
  ) {
    self.mailConnectionService = mailConnectionService
    self.fileImportService = fileImportService
    self.categoryStore = categoryStore
    self.ruleStore = ruleStore
    _notificationSettings = notificationSettings
    self.storageMode = storageMode
    self.accounts = accounts
    self.budgetStore = budgetStore
    self.insightsStore = insightsStore
    self.refreshToken = refreshToken
    self.forcedPermissionDenied = forcedPermissionDenied
  }

  /// The Rules destination, built with the account list. Internal so
  /// `RulesAccountsWiringTests` can check what reaches `RulesScreen`'s
  /// initialiser without rendering the view.
  func rulesScreen() -> RulesScreen {
    RulesScreen(ruleStore: ruleStore, categoryStore: categoryStore, accounts: accounts)
  }

  /// The Budgets destination, or nil when either store is missing (no row).
  /// Carries `refreshToken` (G4). Internal so `SettingsRefreshTokenWiringTests`
  /// can check what reaches `BudgetsScreen`'s initialiser without rendering.
  func budgetsScreen() -> BudgetsScreen? {
    guard let budgetStore, let insightsStore else { return nil }
    return BudgetsScreen(budgetStore: budgetStore, insightsStore: insightsStore, refreshToken: refreshToken)
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        mailGroup
        organizeGroup
        dataGroup
        preferencesGroup
        aboutGroup
      }
      .padding(.horizontal, NomiSpacing.screenGutter)
      .padding(.bottom, NomiSpacing.lg)
    }
    .background(NomiColor.ground)
    .alert(
      "Couldn't re-scan",
      isPresented: Binding(get: { rescanError != nil }, set: { if !$0 { rescanError = nil } })
    ) {
      Button("OK", role: .cancel) { rescanError = nil }
    } message: {
      Text(rescanError ?? "")
    }
    .navigationTitle("Settings")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.large)
    #endif
    .task {
      for await state in mailConnectionService.state {
        connectionState = state
      }
    }
    .task {
      await refreshPermissionStatus()
    }
    // L8: permission can change outside the app (iOS Settings) while Nomi is
    // backgrounded, and this screen's own toggle write is not the only way
    // authorization changes — re-read it whenever either might have moved,
    // rather than only once on first appearance.
    .onChange(of: notificationSettings.budgetAlertsEnabled) { _, _ in
      Task { await refreshPermissionStatus() }
    }
    .onChange(of: scenePhase) { _, newPhase in
      guard newPhase == .active else { return }
      Task { await refreshPermissionStatus() }
    }
  }

  // MARK: - Groups

  private var connectedAddress: String? {
    if case .connected(let address, _) = connectionState {
      return address
    }
    return nil
  }

  private var mailGroup: some View {
    settingsGroup("Mail account", first: true) {
      if let address = connectedAddress {
        connectedMailCard(address: address)
      } else if let title = SettingsLogic.attentionTitle(for: connectionState) {
        disconnectedMailContent(title: title)
      }
    }
  }

  /// Connected: address and status, the scan menu, Manage connection, and the
  /// Not matched disclosure when there is something to show.
  private func connectedMailCard(address: String) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 2) {
        Text(address)
          .nomiTextStyle(.rowBody)
          .foregroundStyle(NomiColor.ink)
        HStack(spacing: NomiSpacing.xxs) {
          Circle()
            .fill(NomiColor.inkSecondary)
            .frame(width: 6, height: 6)
            .accessibilityHidden(true)
          Text(SyncStatusRow.statusText(for: connectionState))
            .nomiTextStyle(.footnote)
            .foregroundStyle(NomiColor.inkSecondary)
        }
      }
      .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
      .padding(.vertical, NomiSpacing.xs)
      rowDivider
      scanMailRow
      rowDivider
      navigationRow("Manage connection") {
        ConnectMailScreen(mailConnectionService: mailConnectionService)
      }
      if !unmatchedSenderRows.isEmpty {
        rowDivider
        notMatchedDisclosure
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .nomiCard()
  }

  /// Not connected: the attention row is the first row of the Mail group. It
  /// draws its own card, so the Not matched disclosure, if any, gets a card
  /// of its own beneath it.
  private func disconnectedMailContent(title: String) -> some View {
    VStack(alignment: .leading, spacing: NomiSpacing.cardGap) {
      NavigationLink {
        ConnectMailScreen(mailConnectionService: mailConnectionService)
      } label: {
        NomiAttentionRow(systemImage: "envelope", title: title, message: nil)
      }
      .buttonStyle(.plain)
      if !unmatchedSenderRows.isEmpty {
        notMatchedDisclosure
          .frame(maxWidth: .infinity, alignment: .leading)
          .nomiCard()
      }
    }
  }

  /// One "Scan mail" row that opens a menu. Both actions are the same two as
  /// before: `rescan()` (syncNow) and `scanRecent()` (6 months).
  private var scanMailRow: some View {
    Menu {
      Button("Force re-scan") {
        rescan()
      }
      Button("Scan last 6 months") {
        scanRecent()
      }
    } label: {
      HStack(spacing: NomiSpacing.xs) {
        Text("Scan mail")
          .nomiTextStyle(.rowTitle)
          .foregroundStyle(NomiColor.navy)
        Spacer(minLength: 0)
        if isRescanning || isScanningRecent {
          ProgressView()
        } else {
          Image(systemName: "ellipsis")
            .foregroundStyle(NomiColor.inkSecondary)
            .accessibilityHidden(true)
        }
      }
      .frame(maxWidth: .infinity, minHeight: NomiSpacing.rowMinHeight, alignment: .leading)
      .contentShape(Rectangle())
    }
  }

  /// Shown only when there are unmatched senders. The rows are domain and
  /// count, as before, and sit under one disclosure row in place of the old
  /// card of grey captions.
  private var notMatchedDisclosure: some View {
    DisclosureGroup {
      VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
        ForEach(unmatchedSenderRows, id: \.self) { row in
          Text(row)
            .nomiTextStyle(.caption)
            .foregroundStyle(NomiColor.inkSecondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.bottom, NomiSpacing.xs)
    } label: {
      Text(SettingsLogic.notMatchedTitle(count: unmatchedSenderRows.count))
        .nomiTextStyle(.rowBody)
        .foregroundStyle(NomiColor.ink)
    }
    .disclosureGroupStyle(SettingsDisclosureStyle())
  }

  private var organizeGroup: some View {
    settingsGroup("Organize") {
      VStack(alignment: .leading, spacing: 0) {
        navigationRow("Categories") {
          CategoriesScreen(categoryStore: categoryStore)
        }
        rowDivider
        if let budgets = budgetsScreen() {
          navigationRow("Budgets") {
            budgets
          }
          rowDivider
        }
        navigationRow("Rules") {
          rulesScreen()
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .nomiCard()
    }
  }

  private var dataGroup: some View {
    settingsGroup("Data") {
      VStack(alignment: .leading, spacing: 0) {
        navigationRow("Import from file") {
          ImportEntryView(fileImportService: fileImportService)
        }
        rowDivider
        iCloudRow
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .nomiCard()
    }
  }

  private var preferencesGroup: some View {
    settingsGroup("Preferences") {
      VStack(alignment: .leading, spacing: 0) {
        Toggle(isOn: budgetAlertsBinding) {
          Text("Budget Alerts")
            .nomiTextStyle(.rowBody)
            .foregroundStyle(NomiColor.ink)
        }
        .tint(NomiColor.navy)
        .disabled(permissionDenied)
        .frame(maxWidth: .infinity, minHeight: NomiSpacing.rowMinHeight, alignment: .leading)
        if NotificationToggleDisplay.showsPermissionExplanation(permissionDenied: permissionDenied) {
          Text("Notifications are turned off for Nomi in iOS Settings, so budget alerts can't be delivered.")
            .nomiTextStyle(.caption)
            .foregroundStyle(NomiColor.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, NomiSpacing.xs)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .nomiCard()
    }
  }

  /// The About row, on its own card below the groups, as the artboard draws it.
  private var aboutGroup: some View {
    VStack(alignment: .leading, spacing: 0) {
      navigationRow("About") {
        AboutScreen()
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .nomiCard()
    .padding(.top, 18)
  }

  // MARK: - Rows

  /// B11, then U9b, now ST. The value is `StorageModeDisplay.text`, read-only.
  /// The caption under it stays for every state that is not syncing, so the
  /// reason is not lost in the restyle.
  private var iCloudRow: some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
      HStack(alignment: .firstTextBaseline, spacing: NomiSpacing.xs) {
        Text("iCloud sync")
          .nomiTextStyle(.rowBody)
          .foregroundStyle(NomiColor.ink)
        Spacer(minLength: 0)
        Text(StorageModeDisplay.text(for: storageMode))
          .nomiTextStyle(.rowBody)
          .foregroundStyle(storageMode.isSyncing ? NomiColor.inkDeep : NomiColor.ink)
          .multilineTextAlignment(.trailing)
      }
      if let caption = StorageModeDisplay.caption(for: storageMode) {
        Text(caption)
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.inkSecondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .frame(maxWidth: .infinity, minHeight: NomiSpacing.rowMinHeight, alignment: .leading)
    .padding(.vertical, NomiSpacing.xs)
  }

  /// A label that opens a destination, with a trailing chevron. Tap target is
  /// the full row, at least 52 pt high.
  private func navigationRow<Destination: View>(
    _ title: String,
    @ViewBuilder destination: @escaping () -> Destination
  ) -> some View {
    NavigationLink {
      destination()
    } label: {
      HStack(spacing: NomiSpacing.xs) {
        Text(title)
          .nomiTextStyle(.rowBody)
          .foregroundStyle(NomiColor.ink)
        Spacer(minLength: 0)
        RowChevron()
      }
      .frame(maxWidth: .infinity, minHeight: NomiSpacing.rowMinHeight, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  /// A section label and the card under it. The label is `label` style in
  /// `inkDeep`, 18 pt above (none for the first group) and 8 pt below.
  private func settingsGroup<Content: View>(
    _ title: String,
    first: Bool = false,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title)
        .nomiTextStyle(.label)
        .foregroundStyle(NomiColor.inkDeep)
        .accessibilityAddTraits(.isHeader)
        .padding(.top, first ? 0 : 18)
        .padding(.bottom, NomiSpacing.xs)
        .padding(.horizontal, NomiSpacing.xxs)
        .frame(maxWidth: .infinity, alignment: .leading)
      content()
    }
  }

  /// The hairline between rows inside a card: `separator`, inset by the card's
  /// own padding, as the artboard draws it.
  private var rowDivider: some View {
    Rectangle()
      .fill(NomiColor.separator)
      .frame(height: 1)
      .accessibilityHidden(true)
  }

  private var budgetAlertsBinding: Binding<Bool> {
    Binding(
      get: { NotificationToggleDisplay.isOn(settings: notificationSettings, permissionDenied: permissionDenied) },
      set: { newValue in
        guard !permissionDenied else { return }
        notificationSettings.budgetAlertsEnabled = newValue
      }
    )
  }

  private var unmatchedSenderRows: [String] {
    guard let lastSyncSummary else { return [] }
    return UnmatchedSenderDisplay.rows(for: lastSyncSummary.unmatchedSenders)
  }

  /// The `try?` here swallowed every re-scan failure - a wrong password, a
  /// dropped socket, a server that said no - and left the button springing
  /// back with nothing shown. F3's pattern, the one `TransactionDetailScreen`
  /// already uses: `do/catch` into an `.alert`.
  private func rescan() {
    isRescanning = true
    rescanError = nil
    Task {
      defer { isRescanning = false }
      do {
        lastSyncSummary = try await SettingsActions.rescan(using: mailConnectionService)
      } catch {
        rescanError = error.localizedDescription
      }
    }
  }

  /// M7: same shape as `rescan()` — its own loading flag, so the menu shows
  /// which action is running, but the same `lastSyncSummary`/`rescanError`,
  /// since both feed the same "Not matched" list and the same failure alert.
  private func scanRecent() {
    isScanningRecent = true
    rescanError = nil
    Task {
      defer { isScanningRecent = false }
      do {
        lastSyncSummary = try await SettingsActions.scanRecent(using: mailConnectionService)
      } catch {
        rescanError = error.localizedDescription
      }
    }
  }

  private func refreshPermissionStatus() async {
    if let forcedPermissionDenied {
      permissionDenied = forcedPermissionDenied
      return
    }
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    permissionDenied = settings.authorizationStatus == .denied
  }
}

/// The trailing chevron on a settings row: 16 pt, `inkSecondary`, hidden from
/// VoiceOver because the row is the control.
private struct RowChevron: View {
  var body: some View {
    Image(systemName: "chevron.right")
      .resizable()
      .scaledToFit()
      .frame(width: 16, height: 16)
      .foregroundStyle(NomiColor.inkSecondary)
      .accessibilityHidden(true)
  }
}

/// The "Not matched" disclosure with its chevron on the trailing edge, as the
/// artboard draws it. The default style puts the chevron on the leading edge.
private struct SettingsDisclosureStyle: DisclosureGroupStyle {
  func makeBody(configuration: Configuration) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Button {
        withAnimation(.easeInOut(duration: 0.2)) {
          configuration.isExpanded.toggle()
        }
      } label: {
        HStack(spacing: NomiSpacing.xs) {
          configuration.label
          Spacer(minLength: 0)
          RowChevron()
            .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
        }
        .frame(maxWidth: .infinity, minHeight: NomiSpacing.rowMinHeight, alignment: .leading)
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

/// M7 done-when: "mail section with both buttons" — `FakeMailConnectionService`
/// only reaches `.connected` live, via `connect()`, which a static preview
/// never calls. `ConnectedFakeMailConnectionService` already exists for
/// exactly this (`Onboarding/OnboardingPreviewSupport.swift`, internal to
/// this module, not edited here) and starts already connected.
#Preview("Settings — mail connected, scan menu, light") {
  NavigationStack {
    SettingsScreen(
      mailConnectionService: ConnectedFakeMailConnectionService(),
      fileImportService: FakeFileImportService(),
      categoryStore: FakeCategoryStore(),
      ruleStore: FakeRuleStore(),
      notificationSettings: .constant(NotificationSettings(budgetAlertsEnabled: true, thresholdFraction: 0.9))
    )
  }
  .modelContainer(EntryRulesPreviewSupport.makeRulesContainer())
  .preferredColorScheme(.light)
}

#Preview("Settings — with Budgets row, light") {
  NavigationStack {
    SettingsScreen(
      mailConnectionService: ConnectedFakeMailConnectionService(),
      fileImportService: FakeFileImportService(),
      categoryStore: FakeCategoryStore(),
      ruleStore: FakeRuleStore(),
      notificationSettings: .constant(NotificationSettings(budgetAlertsEnabled: true, thresholdFraction: 0.9)),
      budgetStore: FakeBudgetStore(budgets: []),
      insightsStore: BudgetsPreviewSupport.makeInsightsStore(progress: [])
    )
  }
  .modelContainer(EntryRulesPreviewSupport.makeRulesContainer())
  .preferredColorScheme(.light)
}

#Preview("Settings — alerts on, light") {
  NavigationStack {
    SettingsScreen(
      mailConnectionService: FakeMailConnectionService(),
      fileImportService: FakeFileImportService(),
      categoryStore: FakeCategoryStore(),
      ruleStore: FakeRuleStore(),
      notificationSettings: .constant(NotificationSettings(budgetAlertsEnabled: true, thresholdFraction: 0.9))
    )
  }
  .modelContainer(EntryRulesPreviewSupport.makeRulesContainer())
  .preferredColorScheme(.light)
}

#Preview("Settings — iCloud sync off, light") {
  NavigationStack {
    SettingsScreen(
      mailConnectionService: FakeMailConnectionService(),
      fileImportService: FakeFileImportService(),
      categoryStore: FakeCategoryStore(),
      ruleStore: FakeRuleStore(),
      notificationSettings: .constant(NotificationSettings(budgetAlertsEnabled: true, thresholdFraction: 0.9)),
      // Not "Not entitled to use CloudKit", which is what this said before:
      // U9b established that a missing entitlement never surfaces as a
      // construction error, so that fixture modelled a state that cannot
      // happen. `.localOnly` is reached by a store that will not open.
      storageMode: .localOnly(reason: "SwiftDataError: could not open the persistent store")
    )
  }
  .modelContainer(EntryRulesPreviewSupport.makeRulesContainer())
  .preferredColorScheme(.light)
}

#Preview("Settings — iCloud signed out, light") {
  // U9b's state, and the one a user is most likely to be in: the container
  // constructed fine, so B11's preview above cannot show it. Sync is paused,
  // not failed, and the caption says where to go rather than what broke.
  NavigationStack {
    SettingsScreen(
      mailConnectionService: FakeMailConnectionService(),
      fileImportService: FakeFileImportService(),
      categoryStore: FakeCategoryStore(),
      ruleStore: FakeRuleStore(),
      notificationSettings: .constant(NotificationSettings(budgetAlertsEnabled: true, thresholdFraction: 0.9)),
      storageMode: .cloudKitPaused(.noAccount)
    )
  }
  .modelContainer(EntryRulesPreviewSupport.makeRulesContainer())
  .preferredColorScheme(.light)
}

#Preview("Settings — alerts off, light") {
  NavigationStack {
    SettingsScreen(
      mailConnectionService: FakeMailConnectionService(),
      fileImportService: FakeFileImportService(),
      categoryStore: FakeCategoryStore(),
      ruleStore: FakeRuleStore(),
      notificationSettings: .constant(NotificationSettings(budgetAlertsEnabled: false, thresholdFraction: 0.9))
    )
  }
  .modelContainer(EntryRulesPreviewSupport.makeRulesContainer())
  .preferredColorScheme(.light)
}

#Preview("Settings — permission denied, light") {
  NavigationStack {
    SettingsScreen(
      mailConnectionService: FakeMailConnectionService(),
      fileImportService: FakeFileImportService(),
      categoryStore: FakeCategoryStore(),
      ruleStore: FakeRuleStore(),
      notificationSettings: .constant(NotificationSettings(budgetAlertsEnabled: true, thresholdFraction: 0.9)),
      forcedPermissionDenied: true
    )
  }
  .modelContainer(EntryRulesPreviewSupport.makeRulesContainer())
  .preferredColorScheme(.light)
}
