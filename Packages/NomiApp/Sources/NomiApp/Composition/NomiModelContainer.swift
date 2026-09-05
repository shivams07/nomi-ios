import Foundation
import NomiCore
import OSLog
import SwiftData

/// The real store: SwiftData over the **CloudKit private database**.
///
/// Two things about the models make this work, and both were decided in U1
/// rather than here: every property carries a default value, and no uniqueness
/// constraint is declared anywhere. CloudKit requires the first and forbids the
/// second — which is also the root of R5 (two devices can create duplicate rows
/// that only `IngestPipeline.reconcile()` can collapse) and of R16 (duplicate
/// budget notifications). Those are accepted costs, not oversights.
public enum NomiModelContainer {
  /// Matches `NomiCore.InMemoryModelContainer.shared` exactly. A model missing
  /// from one and present in the other is a store that opens in the app and
  /// traps in a preview, or the reverse.
  public static let schema = Schema([
    Transaction.self,
    NomiCore.Category.self,
    Budget.self,
    BudgetAlertLog.self,
    Rule.self,
    Account.self,
    AccountBinding.self,
    ColumnMappingRecord.self,
  ])

  /// The identifier in `App/Nomi.entitlements`. Named explicitly rather than
  /// left to `.automatic` so a mismatch between code and entitlement is a
  /// visible constant, not a silent fallback to a container nobody meant.
  public static let cloudKitContainerIdentifier = "iCloud.com.shivams07.nomi"

  public static func makeCloudKit() throws -> ModelContainer {
    try ModelContainer(
      for: schema,
      configurations: [
        ModelConfiguration(
          schema: schema,
          cloudKitDatabase: .private(cloudKitContainerIdentifier)
        )
      ]
    )
  }

  /// Local-only, same schema. Not a test double: it is what the app runs on
  /// when CloudKit is genuinely unavailable.
  public static func makeLocal() throws -> ModelContainer {
    try ModelContainer(
      for: schema,
      configurations: [ModelConfiguration(schema: schema, cloudKitDatabase: .none)]
    )
  }

  /// What the app actually calls.
  ///
  /// **The fallback is the point.** Constructing a CloudKit-backed container
  /// fails outright when the process has no iCloud entitlement — an
  /// unsigned simulator build, a development build on a machine without the
  /// provisioning profile, a device signed out of iCloud in some
  /// configurations. Letting that `try` propagate turns "sync is unavailable"
  /// into "the app does not launch", and launching is the acceptance criterion
  /// this unit is measured on.
  ///
  /// Falling back loses sync, not data: the schema is identical, so a later
  /// launch that does reach CloudKit reads the same local store and begins
  /// syncing it.
  ///
  /// Only the second failure is fatal, and by then there is nothing to run on.
  ///
  /// **Returns the mode as well as the container (B11).** It used to `print`
  /// and return only the container, so the one person who could see that the
  /// app had silently stopped syncing was whoever had Xcode attached. The
  /// caller now carries the answer as far as Settings.
  public static func makeWithLocalFallback() -> (container: ModelContainer, mode: StorageMode) {
    do {
      return (try makeCloudKit(), .cloudKit)
    } catch {
      // `Logger`, not `print`: a `print` is invisible in a release build and in
      // any sysdiagnose the user could send. This line is the first thing to
      // look for when "my other device does not see my transactions" is
      // reported, so it has to survive leaving the debugger.
      logger.error(
        "CloudKit container unavailable, falling back to local storage: \(error, privacy: .public)")
      return (try! makeLocal(), .localOnly(reason: String(describing: error)))
    }
  }

  private static let logger = Logger(subsystem: "com.shivams07.nomi", category: "storage")
}
