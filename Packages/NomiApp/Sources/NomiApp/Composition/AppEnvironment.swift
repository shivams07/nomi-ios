import Combine
import Foundation
import NomiCore
import NomiIngest
import SwiftData

/// The composition root. Everything the app is made of is constructed here,
/// once, and handed down by `init` — never through an `EnvironmentKey`, which
/// is the shape `NomiPreview`'s eight `Fake*` types establish and every screen
/// was built against (§2.18).
///
/// It is `@MainActor` because most of what it holds is: the store protocols in
/// `NomiCore/Contracts/Stores.swift` are `@MainActor`, and the `ModelContext`
/// the views read through with `@Query` is the container's `mainContext`.
@MainActor
public final class AppEnvironment: ObservableObject {
  public let container: ModelContainer
  public let cache: InsightsCache
  public let coordinator: WriteCoordinator

  public let transactionStore: any TransactionStore
  public let categoryStore: any CategoryStore
  public let ruleStore: any RuleStore
  public let insightsStore: any InsightsStore
  public let budgetStore: any BudgetStore
  public let accountStore: any AccountStore

  public let fileImportService: any FileImportService
  public let mail: MailStack
  public let sync: AppSyncCoordinator
  public let notificationSettings: NotificationSettingsStore
  public let firstRun: FirstRunGate

  private let pipeline: IngestPipeline
  private let credentials: any MailCredentialStoring

  public var mailConnectionService: any MailConnectionService { mail.service }

  public init(
    container: ModelContainer,
    preferences: any KeyValueStoring = UserDefaultsKeyValueStore(),
    credentials: any MailCredentialStoring = KeychainCredentialStore(),
    mailFetcher: any MailFetching = UnavailableMailFetcher(),
    scheduler: any BudgetNotificationScheduling = BudgetNotificationScheduler()
  ) {
    self.container = container
    self.credentials = credentials

    let cache = InsightsCache()
    let coordinator = WriteCoordinator(cache: cache)
    self.cache = cache
    self.coordinator = coordinator

    let context = container.mainContext
    let insightsStore = SwiftDataInsightsStore(context: context, cache: cache)
    self.insightsStore = insightsStore
    self.transactionStore = SwiftDataTransactionStore(context: context, coordinator: coordinator)
    self.categoryStore = SwiftDataCategoryStore(context: context, coordinator: coordinator)
    self.ruleStore = SwiftDataRuleStore(context: context, coordinator: coordinator)
    self.budgetStore = SwiftDataBudgetStore(context: context, coordinator: coordinator)
    self.accountStore = SwiftDataAccountStore(context: context, coordinator: coordinator)

    self.firstRun = FirstRunGate(store: preferences)

    let notificationSettings = NotificationSettingsStore(store: preferences, scheduler: scheduler)
    self.notificationSettings = notificationSettings

    // The pipeline gets its own `ModelContext` inside a `@ModelActor`, off the
    // main actor. That is U4's design, not a choice made here — see
    // `SwiftDataPipelineStore`.
    let pipeline = IngestPipeline(store: SwiftDataPipelineStore(modelContainer: container))
    self.pipeline = pipeline

    let mail = MailStack(
      fetcher: mailFetcher,
      pipeline: pipeline,
      credentials: credentials,
      preferences: preferences
    )
    self.mail = mail
    self.sync = AppSyncCoordinator(mail: mail, pipeline: pipeline)

    // File import writes through the same pipeline mail does. U3b (#17) closed
    // the gap this unit reported: `commit` used to map rows, count them against
    // an in-memory dedupe set and return an `ImportSummary` without ever
    // writing a `Transaction`.
    //
    // It was fixed from the other side of the seam — `FileImportServiceImpl`
    // now takes `any DraftIngesting` — rather than by exposing `RowMapper` and
    // `ParsedRow`, which is what this comment previously said was needed. That
    // is the better fix: the drafts never leave `NomiIngest`, and the composition
    // root supplies the sink instead of reimplementing the mapping.
    //
    // Same `pipeline` instance the mail stack and the sync coordinator hold, so
    // both ingest routes serialize through one actor and one dedupe pass.
    self.fileImportService = FileImportServiceImpl(pipeline: pipeline)

    // MARK: Post-commit wiring
    //
    // Two paths reach the budget observer and they are wired differently on
    // purpose (design v9.5):
    //
    // - The pipeline's own hook goes through `PipelineCommitRelay`, which drops
    //   the aggregate cache *before* the observer reads progress back through
    //   `InsightsStore`. Without that the alert is evaluated against the totals
    //   from before the commit that triggered it.
    // - `WriteCoordinator` — which `BudgetStore.setBudget` uses — already drops
    //   the cache itself, so it holds the observer directly. That is the path
    //   that catches a budget *lowered* under existing spend: no commit, no
    //   pipeline hook, and without it the alert never fires at all.
    let contextProvider = AppBudgetAlertContextProvider(
      insightsStore: insightsStore,
      settingsStore: notificationSettings,
      context: context
    )
    let budgetObserver = BudgetAlertObserver(context: contextProvider, scheduler: scheduler)

    coordinator.setObserver(budgetObserver)

    // The relay is built here, on the main actor, and only the relay crosses
    // into the task. Building it inside the closure would mean sending
    // `WriteCoordinator` — a `@MainActor` class, not `Sendable` — across an
    // isolation boundary.
    let relay = PipelineCommitRelay(coordinator: coordinator, downstream: budgetObserver)
    Task { [pipeline, relay] in
      await pipeline.setObserver(relay)
    }

    // §2.2's opt-in rule. Turning alerts on writes a suppressed log row for
    // every category already over threshold and shows nothing, so opting in
    // mid-month cannot deliver six notifications at once.
    notificationSettings.onAlertsEnabled = { [contextProvider] in
      await contextProvider.suppressCurrentCrossings()
    }
  }

  /// Runs once per launch, before the first frame the user acts on.
  ///
  /// Order matters. Seeding first: a reconcile that ran before the categories
  /// existed would be reconciling an empty store, and the mail reconnect can
  /// produce transactions that reference a seeded category.
  public func bootstrap() async {
    do {
      try DefaultCategorySeed.apply(in: container.mainContext)
      cache.invalidate()
    } catch {
      // A failed seed is survivable — the app runs with no categories and every
      // row reads "Uncategorized" — where a trap here would mean the app cannot
      // launch at all. The next launch retries, because the seed is idempotent
      // by id.
      assertionFailure("Default category seed failed: \(error)")
    }

    await sync.reconcile()
    await mail.reconnectFromKeychain(credentials)
  }
}
