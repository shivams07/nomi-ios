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

  @State private var connectionState: MailConnectionState = .disconnected
  @State private var permissionDenied = false
  @State private var isRescanning = false
  @State private var lastSyncSummary: SyncSummary?
  private let forcedPermissionDenied: Bool?

  public init(
    mailConnectionService: MailConnectionService,
    fileImportService: FileImportService,
    categoryStore: CategoryStore,
    ruleStore: RuleStore,
    notificationSettings: Binding<NotificationSettings>
  ) {
    self.mailConnectionService = mailConnectionService
    self.fileImportService = fileImportService
    self.categoryStore = categoryStore
    self.ruleStore = ruleStore
    _notificationSettings = notificationSettings
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
    forcedPermissionDenied: Bool
  ) {
    self.mailConnectionService = mailConnectionService
    self.fileImportService = fileImportService
    self.categoryStore = categoryStore
    self.ruleStore = ruleStore
    _notificationSettings = notificationSettings
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
      Section {
        NavigationLink("About") {
          AboutScreen()
        }
      }
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

  private func rescan() {
    isRescanning = true
    Task {
      defer { isRescanning = false }
      lastSyncSummary = try? await SettingsActions.rescan(using: mailConnectionService)
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
