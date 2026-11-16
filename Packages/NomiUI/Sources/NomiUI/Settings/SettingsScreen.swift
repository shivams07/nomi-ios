import NomiCore
import NomiPreview
import SwiftData
import SwiftUI
import UserNotifications

/// The Settings screen, drawn to the Moss "Settings" artboard (S9a). Four groups and
/// a card of About, top to bottom: Where transactions come from (Mail alerts, Import a
/// statement, Accounts), How they are sorted (Categories, Auto-categorise), Privacy and
/// data (iCloud sync, Export everything, Erase all Nomi data), Notifications (Budget
/// alerts), then About and privacy. The Face ID, SMS and Weekly summary rows are not
/// drawn (Corrections 8). The store-recovery notice (R7) sits at the top of Privacy and
/// data. Reads `Design/**`.
public struct SettingsScreen: View {
  public let mailConnectionService: MailConnectionService
  public let fileImportService: FileImportService
  public let categoryStore: CategoryStore
  public let ruleStore: RuleStore
  @Binding public var notificationSettings: NotificationSettings
  public let storageMode: StorageMode
  /// The live account list, passed through to `RulesScreen` (its Account picker) and
  /// to the CSV export, where it names each account. `RootView` supplies it.
  public let accounts: [NomiCore.Account]
  /// Reads the Accounts row's count and total, and the all-time export. `nil` shows
  /// the row without a count, and the export says it could not run.
  public let insightsStore: InsightsStore?
  /// The erase seam (S9a). `nil` hides the Erase row, so no preview or test can erase
  /// by accident. `RootView` passes `AppEnvironment.eraser`.
  public let eraser: (any DataErasing)?
  /// True while the OS notification prompt is up, so the Budget alerts row shows a
  /// spinner in place of its switch (R10).
  public let isRequestingNotificationPermission: Bool
  /// G4. Re-reads the Accounts row when the cache generation changes. Stored and read
  /// only through `.task(id:)`.
  public let refreshToken: Int

  @Query(sort: \NomiCore.Category.sortIndex) private var categories: [NomiCore.Category]
  @Query private var rules: [NomiCore.Rule]

  @State private var connectionState: MailConnectionState = .disconnected
  @State private var permissionDenied = false
  /// The Accounts read and the R7 notice (T2a, S9a). See `SettingsModel`.
  @State private var model: SettingsModel
  @State private var share = ReportsShareState()
  @State private var exportError = false
  @State private var showsErase = false
  private let forcedPermissionDenied: Bool?

  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// Every argument after `notificationSettings` defaults, so each existing call site
  /// and preview compiles unchanged. `storeRecovery` reads the R7 record from standard
  /// defaults, so `RootView` needs no change for it; previews pass a fixed notice.
  public init(
    mailConnectionService: MailConnectionService,
    fileImportService: FileImportService,
    categoryStore: CategoryStore,
    ruleStore: RuleStore,
    notificationSettings: Binding<NotificationSettings>,
    storageMode: StorageMode = .cloudKit,
    accounts: [NomiCore.Account] = [],
    insightsStore: InsightsStore? = nil,
    eraser: (any DataErasing)? = nil,
    isRequestingNotificationPermission: Bool = false,
    refreshToken: Int = 0,
    storeRecovery: StoreRecoveryNotice? = StoreRecoveryRecord.load(from: .standard)
  ) {
    self.mailConnectionService = mailConnectionService
    self.fileImportService = fileImportService
    self.categoryStore = categoryStore
    self.ruleStore = ruleStore
    _notificationSettings = notificationSettings
    self.storageMode = storageMode
    self.accounts = accounts
    self.insightsStore = insightsStore
    self.eraser = eraser
    self.isRequestingNotificationPermission = isRequestingNotificationPermission
    self.refreshToken = refreshToken
    _model = State(
      initialValue: SettingsModel(
        storeRecovery: storeRecovery, recoveryDefaults: .standard, insightsStore: insightsStore))
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
    insightsStore: InsightsStore? = nil,
    eraser: (any DataErasing)? = nil,
    isRequestingNotificationPermission: Bool = false,
    refreshToken: Int = 0,
    storeRecovery: StoreRecoveryNotice? = StoreRecoveryRecord.load(from: .standard)
  ) {
    self.mailConnectionService = mailConnectionService
    self.fileImportService = fileImportService
    self.categoryStore = categoryStore
    self.ruleStore = ruleStore
    _notificationSettings = notificationSettings
    self.storageMode = storageMode
    self.accounts = accounts
    self.insightsStore = insightsStore
    self.eraser = eraser
    self.isRequestingNotificationPermission = isRequestingNotificationPermission
    self.refreshToken = refreshToken
    _model = State(
      initialValue: SettingsModel(
        storeRecovery: storeRecovery, recoveryDefaults: .standard, insightsStore: insightsStore))
    self.forcedPermissionDenied = forcedPermissionDenied
  }

  /// The Auto-categorise destination, built with the account list. Internal so
  /// `RulesAccountsWiringTests` can check what reaches `RulesScreen`'s initialiser
  /// without rendering the view.
  func rulesScreen() -> RulesScreen {
    RulesScreen(ruleStore: ruleStore, categoryStore: categoryStore, accounts: accounts)
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        transactionsGroup
        sortedGroup
        privacyGroup
        notificationsGroup
        aboutGroup
      }
      .padding(.horizontal, NomiSpacing.screenGutter)
      .padding(.bottom, NomiSpacing.lg)
    }
    .background(NomiColor.ground)
    .alert("Could not export CSV", isPresented: $exportError) {
      Button("OK", role: .cancel) {}
    }
    .sheet(item: $share.item) { item in
      ReportsShareSheet(url: item.url)
    }
    .sheet(isPresented: $showsErase) {
      if let eraser {
        EraseDataSheet(eraser: eraser)
      }
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
    .task(id: refreshToken) {
      model.loadAccounts()
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

  private var transactionsGroup: some View {
    settingsGroup("Where transactions come from", first: true) {
      VStack(alignment: .leading, spacing: 0) {
        mailAlertsRow
        rowDivider
        valueLinkRow(
          .importStatement, symbol: "doc.text", title: "Import a statement", caption: "CSV or Excel")
        rowDivider
        valueLinkRow(
          .accounts, symbol: "creditcard", title: "Accounts", caption: accountsCaption)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .nomiCard()
    }
  }

  private var sortedGroup: some View {
    settingsGroup("How they are sorted") {
      VStack(alignment: .leading, spacing: 0) {
        pushRow(
          symbol: "square.grid.2x2", title: "Categories",
          caption: SettingsLogic.categoriesText(count: categories.count)
        ) {
          CategoriesScreen(categoryStore: categoryStore)
        }
        rowDivider
        pushRow(
          symbol: "wand.and.stars", title: "Auto-categorise",
          caption: SettingsLogic.merchantsRememberedText(count: merchantsRemembered)
        ) {
          rulesScreen()
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .nomiCard()
    }
  }

  private var privacyGroup: some View {
    settingsGroup("Privacy and data") {
      VStack(alignment: .leading, spacing: NomiSpacing.cardGap) {
        if let storeRecovery = model.storeRecovery {
          storeRecoveryNotice(storeRecovery)
        }
        VStack(alignment: .leading, spacing: 0) {
          iCloudRow
          rowDivider
          actionRow(
            symbol: "square.and.arrow.up", title: "Export everything",
            caption: "One CSV of every transaction", action: exportEverything)
          if eraser != nil {
            rowDivider
            actionRow(
              symbol: "trash", title: "Erase all Nomi data",
              caption: "On this iPhone and in iCloud", destructive: true
            ) {
              showsErase = true
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nomiCard()
      }
    }
  }

  private var notificationsGroup: some View {
    settingsGroup("Notifications") {
      VStack(alignment: .leading, spacing: 0) {
        NomiToggleRow(
          title: "Budget alerts",
          caption: SettingsLogic.budgetAlertsCaption(thresholdFraction: notificationSettings.thresholdFraction),
          isOn: budgetAlertsBinding,
          isPending: isRequestingNotificationPermission
        )
        .disabled(permissionDenied)
        if NotificationToggleDisplay.showsPermissionExplanation(permissionDenied: permissionDenied) {
          Text("Notifications are turned off for Nomi in iOS Settings, so budget alerts can't be delivered.")
            .nomiTextStyle(.caption)
            .foregroundStyle(NomiColor.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
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
      pushRow(
        symbol: "info.circle", title: "About and privacy",
        caption: AboutLogic.versionLine(bundle: .main)
      ) {
        AboutScreen()
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .nomiCard()
    .padding(.top, 18)
  }

  // MARK: - Values

  private var merchantsRemembered: Int {
    SettingsLogic.merchantsRemembered(rules.map { (isSystem: $0.isSystem, isEnabled: $0.isEnabled) })
  }

  /// The Accounts row's caption, read the way the Accounts screen reads it. `nil` when
  /// Settings has no store to read from.
  private var accountsCaption: String? {
    guard let accounts = model.accounts else { return nil }
    switch accounts.state {
    case .loading:
      return "Loading…"
    case .failed:
      return "Couldn’t load your accounts"
    case .loaded:
      return SettingsLogic.accountsText(count: accounts.active.count, totalMinor: accounts.totalMinor)
    }
  }

  private var mailAlertsRow: some View {
    NavigationLink(value: HomeRoute.connectMail) {
      rowBody(
        symbol: "envelope", title: "Mail alerts",
        caption: SettingsLogic.mailStatus(for: connectionState, now: Date()),
        primary: SettingsLogic.mailAddress(for: connectionState),
        valueBelow: true
      ) {
        HStack(spacing: NomiSpacing.xs) {
          NomiTag(SettingsLogic.mailIsOn(connectionState) ? "On" : "Off")
          RowChevron()
        }
      }
    }
    .buttonStyle(.plain)
  }

  /// iCloud sync is a read-only value: its tag is the storage mode's text, its caption
  /// the sentence for the state. The local fallback also offers its reason to copy.
  private var iCloudRow: some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xs) {
      rowBody(
        symbol: "icloud", title: "iCloud sync",
        caption: StorageModeDisplay.caption(for: storageMode),
        valueBelow: true
      ) {
        NomiTag(StorageModeDisplay.text(for: storageMode))
      }
      if let details = SettingsLogic.copyableDetails(for: storageMode) {
        CopyDetailsLink(text: details)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, NomiSpacing.xs)
  }

  // MARK: - Rows

  /// A row that pushes a destination onto the stack, with a chevron.
  private func pushRow<Destination: View>(
    symbol: String,
    title: String,
    caption: String?,
    @ViewBuilder destination: @escaping () -> Destination
  ) -> some View {
    NavigationLink {
      destination()
    } label: {
      rowBody(symbol: symbol, title: title, caption: caption) {
        RowChevron()
      }
    }
    .buttonStyle(.plain)
  }

  /// A row that pushes a Home route (`HomeRoute`), with a chevron. The route is
  /// handled by `RootView`'s Home stack, so Settings itself needs no destination.
  private func valueLinkRow(
    _ route: HomeRoute,
    symbol: String,
    title: String,
    caption: String?
  ) -> some View {
    NavigationLink(value: route) {
      rowBody(symbol: symbol, title: title, caption: caption) {
        RowChevron()
      }
    }
    .buttonStyle(.plain)
  }

  /// A row that does something instead of navigating. Erase's title is in the error colour.
  private func actionRow(
    symbol: String,
    title: String,
    caption: String?,
    destructive: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      rowBody(symbol: symbol, title: title, caption: caption, destructive: destructive) {
        EmptyView()
      }
    }
    .buttonStyle(.plain)
  }

  /// The row's layout: a 42 pt icon tile, a title over an optional caption, and a
  /// trailing value. At accessibility sizes the value moves under the text (label above
  /// value), so no word breaks and nothing is pushed off the card. Words wrap; the
  /// caption never truncates.
  private func rowBody<Trailing: View>(
    symbol: String,
    title: String,
    caption: String?,
    primary: String? = nil,
    destructive: Bool = false,
    valueBelow: Bool = false,
    @ViewBuilder trailing: () -> Trailing
  ) -> some View {
    let stacked = valueBelow && dynamicTypeSize.isAccessibilitySize
    return Group {
      if stacked {
        VStack(alignment: .leading, spacing: NomiSpacing.xs) {
          HStack(alignment: .center, spacing: NomiSpacing.xs) {
            iconTile(symbol: symbol, destructive: destructive)
            textColumn(title: title, primary: primary, caption: caption, destructive: destructive)
          }
          trailing()
        }
      } else {
        HStack(alignment: .center, spacing: NomiSpacing.xs) {
          iconTile(symbol: symbol, destructive: destructive)
          textColumn(title: title, primary: primary, caption: caption, destructive: destructive)
          trailing()
        }
      }
    }
    .frame(maxWidth: .infinity, minHeight: NomiSpacing.rowMinHeight, alignment: .leading)
    .padding(.vertical, NomiSpacing.xs)
    .contentShape(Rectangle())
  }

  private func textColumn(title: String, primary: String?, caption: String?, destructive: Bool) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .nomiTextStyle(.rowTitle)
        .foregroundStyle(destructive ? NomiColor.error : NomiColor.ink)
        .fixedSize(horizontal: false, vertical: true)
      if let primary {
        // One word that can be long (an address): one line, scaled down, then truncated,
        // never broken across lines.
        Text(primary)
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.inkSecondary)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
      }
      if let caption {
        Text(caption)
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.inkSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func iconTile(symbol: String, destructive: Bool) -> some View {
    Image(systemName: symbol)
      .resizable()
      .scaledToFit()
      .frame(width: 18, height: 18)
      .foregroundStyle(destructive ? NomiColor.error : NomiColor.navy)
      .frame(width: 42, height: 42)
      .background(Circle().fill(destructive ? NomiColor.errorTint : NomiColor.iconTile))
      .accessibilityHidden(true)
  }

  /// The R7 notice: says once that the store was moved aside, until Dismiss.
  /// `NomiAttentionRow` draws its own card, so it sits above the Privacy card
  /// rather than inside it.
  private func storeRecoveryNotice(_ notice: StoreRecoveryNotice) -> some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xs) {
      Self.storeRecoveryRow(notice)
      Button("Dismiss") {
        model.dismissStoreRecovery()
      }
      .buttonStyle(NomiSecondaryButtonStyle())
      .frame(maxWidth: .infinity, minHeight: NomiSpacing.minTarget, alignment: .leading)
    }
  }

  /// A section label and the card under it. The label is 13 pt Medium in
  /// `inkSecondary`, 18 pt above (none for the first group) and 8 pt below.
  private func settingsGroup<Content: View>(
    _ title: String,
    first: Bool = false,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title)
        .nomiTextStyle(.subhead)
        .foregroundStyle(NomiColor.inkSecondary)
        .accessibilityAddTraits(.isHeader)
        .padding(.top, first ? 0 : 18)
        .padding(.bottom, NomiSpacing.xs)
        .padding(.horizontal, NomiSpacing.xxs)
        .frame(maxWidth: .infinity, alignment: .leading)
      content()
    }
  }

  /// The hairline between rows inside a card: `separator`, as the artboard draws it.
  private var rowDivider: some View {
    Rectangle()
      .fill(NomiColor.separator)
      .frame(height: 1)
      .accessibilityHidden(true)
  }

  // MARK: - Actions

  private var budgetAlertsBinding: Binding<Bool> {
    Binding(
      get: { NotificationToggleDisplay.isOn(settings: notificationSettings, permissionDenied: permissionDenied) },
      set: { newValue in
        guard !permissionDenied else { return }
        notificationSettings.budgetAlertsEnabled = newValue
      }
    )
  }

  /// Writes every transaction to a CSV and opens its share sheet. A failed read or write
  /// raises the export alert and opens no sheet.
  private func exportEverything() {
    let names = CSVNameMaps(categories: categoryNames, accounts: accountNames)
    do {
      let url = try model.exportEverything(names: names)
      share.item = ReportsShareItem(url: url)
    } catch {
      exportError = true
    }
  }

  /// `uniquingKeysWith` for the same reason as Insights: two devices can insert rows
  /// sharing an id before the first sync, and `uniqueKeysWithValues:` would trap.
  private var categoryNames: [UUID: String] {
    Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
  }

  private var accountNames: [UUID: String] {
    Dictionary(accounts.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
  }

  /// The R7 notice's row. It has no chevron: the notice does not navigate, so
  /// a chevron would look tappable.
  static func storeRecoveryRow(_ notice: StoreRecoveryNotice) -> NomiAttentionRow {
    NomiAttentionRow(
      systemImage: "exclamationmark.triangle",
      title: "Saved data couldn’t be opened",
      message: StoreRecoveryDisplay.caption(for: notice),
      showsChevron: false
    )
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

#Preview("Settings — mail connected, light") {
  NavigationStack {
    SettingsScreen(
      mailConnectionService: ConnectedFakeMailConnectionService(),
      fileImportService: FakeFileImportService(),
      categoryStore: FakeCategoryStore(),
      ruleStore: FakeRuleStore(),
      notificationSettings: .constant(NotificationSettings(budgetAlertsEnabled: true, thresholdFraction: 0.9)),
      insightsStore: FakeInsightsStore(),
      eraser: EraseDataPreviewEraser(scope: .everywhere)
    )
  }
  .modelContainer(EntryRulesPreviewSupport.makeRulesContainer())
  .preferredColorScheme(.light)
}

#Preview("Settings — mail not connected, light") {
  NavigationStack {
    SettingsScreen(
      mailConnectionService: FakeMailConnectionService(),
      fileImportService: FakeFileImportService(),
      categoryStore: FakeCategoryStore(),
      ruleStore: FakeRuleStore(),
      notificationSettings: .constant(NotificationSettings(budgetAlertsEnabled: true, thresholdFraction: 0.9)),
      insightsStore: FakeInsightsStore(),
      eraser: EraseDataPreviewEraser(scope: .everywhere)
    )
  }
  .modelContainer(EntryRulesPreviewSupport.makeRulesContainer())
  .preferredColorScheme(.light)
}

#Preview("Settings — iCloud on this device only, light") {
  NavigationStack {
    SettingsScreen(
      mailConnectionService: FakeMailConnectionService(),
      fileImportService: FakeFileImportService(),
      categoryStore: FakeCategoryStore(),
      ruleStore: FakeRuleStore(),
      notificationSettings: .constant(NotificationSettings(budgetAlertsEnabled: true, thresholdFraction: 0.9)),
      // Not "Not entitled to use CloudKit": U9b established that a missing entitlement
      // never surfaces as a construction error. `.localOnly` is reached by a store that
      // will not open, and its reason goes to "Copy details".
      storageMode: .localOnly(reason: "SwiftDataError: could not open the persistent store"),
      insightsStore: FakeInsightsStore(),
      eraser: EraseDataPreviewEraser(scope: .thisDeviceOnly)
    )
  }
  .modelContainer(EntryRulesPreviewSupport.makeRulesContainer())
  .preferredColorScheme(.light)
}

#Preview("Settings — not being saved, light") {
  // R7c: the store would not open at all, so nothing this launch adds is kept.
  // The caption is the reason alone, with no "safe" sentence.
  NavigationStack {
    SettingsScreen(
      mailConnectionService: FakeMailConnectionService(),
      fileImportService: FakeFileImportService(),
      categoryStore: FakeCategoryStore(),
      ruleStore: FakeRuleStore(),
      notificationSettings: .constant(NotificationSettings(budgetAlertsEnabled: true, thresholdFraction: 0.9)),
      storageMode: .inMemory(
        reason: "Nomi couldn’t open your saved data this time. Nothing has been changed or deleted. Close Nomi and open it again; anything you add before then won’t be kept.")
    )
  }
  .modelContainer(EntryRulesPreviewSupport.makeRulesContainer())
  .preferredColorScheme(.light)
}

#Preview("Settings — iCloud signed out, light") {
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

#Preview("Settings — store recovered, light") {
  NavigationStack {
    SettingsScreen(
      mailConnectionService: FakeMailConnectionService(),
      fileImportService: FakeFileImportService(),
      categoryStore: FakeCategoryStore(),
      ruleStore: FakeRuleStore(),
      notificationSettings: .constant(NotificationSettings(budgetAlertsEnabled: true, thresholdFraction: 0.9)),
      storeRecovery: StoreRecoveryNotice(
        movedAt: Date(timeIntervalSince1970: 1_794_648_612),
        fileName: "default-20261114T093012.store"
      )
    )
  }
  .modelContainer(EntryRulesPreviewSupport.makeRulesContainer())
  .preferredColorScheme(.light)
}
