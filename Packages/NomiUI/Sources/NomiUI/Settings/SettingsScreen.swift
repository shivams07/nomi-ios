import NomiCore
import NomiPreview
import SwiftUI
import UserNotifications

/// The Settings screen (U7, v5 addition — folded in here rather than a
/// separate unit, since its two largest rows ARE this unit's other screens:
/// mail account management is the connect/disconnect flow, and the CSV import
/// entry point is the import flow). Contains: connected-account row
/// (connect/disconnect/force re-scan), CSV import entry, navigation to
/// Categories and Rules (U6's screens, public for exactly this reason), the
/// budget-alert toggle, and an about/version row.
/// Reads `Design/**`. Must not edit it.
public struct SettingsScreen: View {
  public let mailConnectionService: MailConnectionService
  public let fileImportService: FileImportService
  public let categoryStore: CategoryStore
  public let ruleStore: RuleStore
  @Binding public var notificationSettings: NotificationSettings
  public let storageMode: StorageMode

  @State private var connectionState: MailConnectionState = .disconnected
  @State private var permissionDenied = false
  @State private var isRescanning = false
  @State private var lastSyncSummary: SyncSummary?
  @State private var rescanError: String?
  private let forcedPermissionDenied: Bool?

  /// `storageMode` defaults to `.cloudKit` so every existing call site and
  /// preview compiles unchanged; `RootView` passes the real value.
  public init(
    mailConnectionService: MailConnectionService,
    fileImportService: FileImportService,
    categoryStore: CategoryStore,
    ruleStore: RuleStore,
    notificationSettings: Binding<NotificationSettings>,
    storageMode: StorageMode = .cloudKit
  ) {
    self.mailConnectionService = mailConnectionService
    self.fileImportService = fileImportService
    self.categoryStore = categoryStore
    self.ruleStore = ruleStore
    _notificationSettings = notificationSettings
    self.storageMode = storageMode
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
    storageMode: StorageMode = .cloudKit
  ) {
    self.mailConnectionService = mailConnectionService
    self.fileImportService = fileImportService
    self.categoryStore = categoryStore
    self.ruleStore = ruleStore
    _notificationSettings = notificationSettings
    self.storageMode = storageMode
    self.forcedPermissionDenied = forcedPermissionDenied
  }

  public var body: some View {
    List {
      mailSection
      if !unmatchedSenderRows.isEmpty {
        Section("Not Matched") {
          ForEach(unmatchedSenderRows, id: \.self) { row in
            Text(row)
              .nomiTextStyle(.caption)
              .foregroundStyle(NomiColor.textTertiary)
          }
        }
      }
      Section("Organize") {
        NavigationLink("Categories") {
          CategoriesScreen(categoryStore: categoryStore)
        }
        NavigationLink("Rules") {
          RulesScreen(ruleStore: ruleStore, categoryStore: categoryStore)
        }
      }
      Section("Import") {
        NavigationLink("Import from File") {
          ImportEntryView(fileImportService: fileImportService)
        }
      }
      notificationsSection
      storageSection
      Section {
        NavigationLink("About") {
          AboutScreen()
        }
      }
    }
    .alert(
      "Couldn't re-scan",
      isPresented: Binding(get: { rescanError != nil }, set: { if !$0 { rescanError = nil } })
    ) {
      Button("OK", role: .cancel) { rescanError = nil }
    } message: {
      Text(rescanError ?? "")
    }
    .scrollContentBackground(.hidden)
    .background(NomiColor.surfaceCanvas)
    .navigationTitle("Settings")
    .task {
      for await state in mailConnectionService.state {
        connectionState = state
      }
    }
    .task {
      if let forcedPermissionDenied {
        permissionDenied = forcedPermissionDenied
        return
      }
      let settings = await UNUserNotificationCenter.current().notificationSettings()
      permissionDenied = settings.authorizationStatus == .denied
    }
  }

  private var mailSection: some View {
    Section("Mail Account") {
      switch connectionState {
      case .connected(let address, _):
        VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
          Text(address)
            .nomiTextStyle(.body)
            .foregroundStyle(NomiColor.textPrimary)
          SyncStatusRow(state: connectionState)
        }
        Button {
          rescan()
        } label: {
          if isRescanning {
            ProgressView()
          } else {
            Text("Force Re-scan")
          }
        }
        NavigationLink("Manage Connection") {
          ConnectMailScreen(mailConnectionService: mailConnectionService)
        }
      case .disconnected, .connecting, .failed:
        NavigationLink {
          ConnectMailScreen(mailConnectionService: mailConnectionService)
        } label: {
          VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
            Text("Connect Mail")
              .nomiTextStyle(.body)
              .foregroundStyle(NomiColor.textPrimary)
            SyncStatusRow(state: connectionState)
          }
        }
      }
    }
  }

  private var notificationsSection: some View {
    Section("Notifications") {
      Toggle(
        "Budget Alerts",
        isOn: Binding(
          get: { NotificationToggleDisplay.isOn(settings: notificationSettings, permissionDenied: permissionDenied) },
          set: { newValue in
            guard !permissionDenied else { return }
            notificationSettings.budgetAlertsEnabled = newValue
          }
        )
      )
      .disabled(permissionDenied)
      if NotificationToggleDisplay.showsPermissionExplanation(permissionDenied: permissionDenied) {
        Text("Notifications are turned off for Nomi in iOS Settings, so budget alerts can't be delivered.")
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.textTertiary)
      }
    }
  }

  private var unmatchedSenderRows: [String] {
    guard let lastSyncSummary else { return [] }
    return UnmatchedSenderDisplay.rows(for: lastSyncSummary.unmatchedSenders)
  }

  /// B11. One row, always shown - "On" is worth saying too, because the whole
  /// problem was that the app never mentioned iCloud at all and the user had
  /// no way to tell which state they were in.
  private var storageSection: some View {
    Section("Storage") {
      VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
        HStack {
          Text("iCloud sync")
            .nomiTextStyle(.body)
            .foregroundStyle(NomiColor.textPrimary)
          Spacer()
          Text(StorageModeDisplay.text(for: storageMode))
            .nomiTextStyle(.body)
            .foregroundStyle(
              storageMode.isSyncing ? NomiColor.textSecondary : NomiColor.textPrimary)
        }
        if let caption = StorageModeDisplay.caption(for: storageMode) {
          Text(caption)
            .nomiTextStyle(.caption)
            .foregroundStyle(NomiColor.textTertiary)
        }
      }
    }
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
}

#Preview("Settings — alerts on, dark") {
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
  .preferredColorScheme(.dark)
}

#Preview("Settings — iCloud sync off, dark") {
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
  .preferredColorScheme(.dark)
}

#Preview("Settings — iCloud signed out, dark") {
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
  .preferredColorScheme(.dark)
}

#Preview("Settings — alerts off, dark") {
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
  .preferredColorScheme(.dark)
}

#Preview("Settings — permission denied, dark") {
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
  .preferredColorScheme(.dark)
}
