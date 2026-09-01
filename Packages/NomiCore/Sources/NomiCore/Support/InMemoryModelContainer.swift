import Foundation
import SwiftData

/// An in-memory `ModelContainer` for `NomiApp` to hand to `NomiPreview`/UI
/// previews and, on-device, for anything that needs a scratch container.
///
/// **Usable from `swift test` under XCTest. Traps under swift-testing.** This
/// note used to say `swift test` could not construct a `ModelContainer` at all
/// in this CI, and that "tests and `NomiPreview` must not construct `@Model`
/// instances". The first half holds only under swift-testing; the second
/// names the wrong thing entirely, and says nothing this project has ever
/// measured about `NomiPreview`'s previews, which run in Xcode and not here.
/// Measured 2026-09-01 on macos-14 / Xcode 16.2, five CI runs:
///
/// |            | XCTest | swift-testing |
/// |------------|--------|---------------|
/// | NomiCore   | passes | traps         |
/// | NomiIngest | passes | traps         |
///
/// The failure is always `SwiftData/DataStoreCoreData.swift:32: Fatal error:
/// Unable to determine Bundle Name`, and `swift test` exits on signal 5,
/// taking the rest of that package's tests down with it.
///
/// Three things the measurements pin down:
///
/// - **It fires on `ModelContainer` construction, not on `@Model`
///   construction.** Nothing about declaring, instantiating or inserting a
///   `@Model` is a problem; the store load is. `shared` below traps inside its
///   own `try!`, before it returns.
/// - **It is not the package.** In one `swift test` invocation on the
///   NomiIngest binary, 207 XCTest tests passed — five of them building
///   containers and driving a real `@ModelActor` — and then the single
///   swift-testing test in the same target trapped constructing a two-model
///   container. Same commit, same schema, same build.
/// - **No `Package.swift` change is needed.** The `Info.plist`-via-
///   `linkerSettings` escalation the old note pointed at was never the fix,
///   and U0's freeze on that file costs nothing here.
///
/// **Why the runner changes it is not established.** `swift test` launches the
/// two testing libraries separately and only the swift-testing launch fails to
/// resolve a bundle name; the mechanism past that is guesswork and is
/// deliberately not written down.
///
/// To test anything that touches a container — this type, a store, a
/// `@ModelActor` — write the test in XCTest. The two worked examples are
/// `SwiftDataContainerTests` in this package and `SwiftDataPipelineStoreTests`
/// in NomiIngest; both carry a paragraph saying why they are not
/// swift-testing, because in this package that looks like an oversight.
///
/// NomiCore is the only package here whose tests are swift-testing, which is
/// why the constraint looked universal from inside this file, and why NomiApp,
/// NomiUI and NomiIngest could have been testing their `@Model` code all along.
///
/// Several other files still describe themselves as compile-verified only and
/// cite the old claim — `SwiftDataPipelineStore`, `SwiftDataColumnMappingStore`,
/// `SwiftDataInsightsStore`, `DefaultCategorySeed`, `PipelineTypes`,
/// `InsightsAggregator`. Those are stale as written and are deliberately left
/// alone here: what to do about them is a repo-wide test-strategy call, not
/// this file's.
public enum InMemoryModelContainer {
  public static let shared: ModelContainer = {
    let schema = Schema([
      Transaction.self,
      Category.self,
      Budget.self,
      BudgetAlertLog.self,
      Rule.self,
      Account.self,
      AccountBinding.self,
      ColumnMappingRecord.self,
    ])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    return try! ModelContainer(for: schema, configurations: [configuration])
  }()
}
