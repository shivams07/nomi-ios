import Foundation
import NomiCore
import NomiIngest
import SwiftData
import XCTest

@testable import NomiApp

/// C4, the whole loop, on a real container: the user assigns an account once,
/// and the app stops asking.
///
/// Three halves that look like one and are not — learning the binding, applying
/// it to the rows already sitting in the review queue, and un-flagging only the
/// rows whose flag *was* the missing account. A `setAccount` with any one of
/// them missing is correct on the row the user tapped and useless everywhere
/// else, which is what the behaviour before this unit was.
///
/// A `ModelContainer` under `swift test` is fine in XCTest and traps under
/// swift-testing (see `InMemoryModelContainer`), which is why this is XCTest,
/// like `AccountStoreTests` next to it.
@MainActor
final class AccountBindingTests: XCTestCase {

  private let domain = "alerts.hdfcbank.net"
  private let fragment = "4471"

  // MARK: - 1. Learn

  func testAssigningAnAccountToAMailRowWritesOneBinding() throws {
    let (store, context, _) = try makeStore()
    let account = UUID()
    let row = insertMailRow(into: context)

    try store.setAccount(row.id, to: account)

    let bindings = try context.fetch(FetchDescriptor<AccountBinding>())
    XCTAssertEqual(bindings.count, 1)
    XCTAssertEqual(bindings.first?.senderDomain, domain)
    XCTAssertEqual(bindings.first?.cardFragment, fragment)
    XCTAssertEqual(bindings.first?.accountID, account)
  }

  func testReassigningUpdatesTheBindingRatherThanAddingASecond() throws {
    let (store, context, _) = try makeStore()
    let first = UUID()
    let second = UUID()
    let row = insertMailRow(into: context)

    try store.setAccount(row.id, to: first)
    try store.setAccount(row.id, to: second)

    let bindings = try context.fetch(FetchDescriptor<AccountBinding>())
    XCTAssertEqual(bindings.count, 1)
    XCTAssertEqual(bindings.first?.accountID, second)
  }

  func testUnassigningLearnsNothingAndDeletesNothing() throws {
    let (store, context, _) = try makeStore()
    let account = UUID()
    let row = insertMailRow(into: context)
    try store.setAccount(row.id, to: account)

    try store.setAccount(row.id, to: nil)

    XCTAssertNil(row.accountID)
    let bindings = try context.fetch(FetchDescriptor<AccountBinding>())
    XCTAssertEqual(
      bindings.count, 1,
      "correcting one row does not retract what the user taught")
    XCTAssertEqual(bindings.first?.accountID, account)
  }

  /// A row with no `senderDomain`/`cardFragment` is every row already on the
  /// device before this shipped. Assigning it must work and must learn nothing.
  func testARowWithNoCapturedSenderLearnsNothing() throws {
    let (store, context, _) = try makeStore()
    let row = insertMailRow(into: context, senderDomain: nil, cardFragment: nil)

    try store.setAccount(row.id, to: UUID())

    XCTAssertNotNil(row.accountID)
    XCTAssertTrue(try context.fetch(FetchDescriptor<AccountBinding>()).isEmpty)
  }

  func testAManualRowLearnsNothingEvenIfItSomehowCarriesAKey() throws {
    let (store, context, _) = try makeStore()
    let row = insertMailRow(into: context)
    row.source = .manual
    try context.save()

    try store.setAccount(row.id, to: UUID())

    XCTAssertTrue(
      try context.fetch(FetchDescriptor<AccountBinding>()).isEmpty,
      "bindings are a fact about mail, not about rows the user typed")
  }

  // MARK: - 2. Apply to siblings, 3. un-flag narrowly

  /// The test that carries the unit. One tap: the sibling gets the account and
  /// loses its flag, the Layer-2 sibling gets the account and keeps its flag,
  /// the already-assigned row is untouched, and a different card is untouched.
  func testOneAssignmentReachesEverySiblingAndUnflagsOnlyTheRightOnes() throws {
    let (store, context, _) = try makeStore()
    let account = UUID()
    let other = UUID()

    let tapped = insertMailRow(into: context)
    let sibling = insertMailRow(into: context)
    let heuristicSibling = insertMailRow(into: context, reason: .heuristic)
    let differentCard = insertMailRow(into: context, cardFragment: "8812")
    let alreadyAssigned = insertMailRow(
      into: context, accountID: other, needsReview: false, reason: nil)

    try store.setAccount(tapped.id, to: account)

    XCTAssertEqual(tapped.accountID, account)
    XCTAssertFalse(tapped.needsReview)

    XCTAssertEqual(sibling.accountID, account, "same domain and card, so the same account")
    XCTAssertFalse(sibling.needsReview, "its flag WAS the missing account")

    XCTAssertEqual(heuristicSibling.accountID, account)
    XCTAssertTrue(
      heuristicSibling.needsReview,
      "Layer 2 guessed the amount too; an account does not make that reviewed")

    XCTAssertNil(differentCard.accountID, "a different card is a different account")
    XCTAssertTrue(differentCard.needsReview)

    XCTAssertEqual(alreadyAssigned.accountID, other, "not for this call to overwrite")
  }

  /// The `mergedCount == 1` gate. A row merged since insert may carry a
  /// pipeline flag its reason knows nothing about, so the reason alone is not
  /// enough to clear it.
  func testAMergedRowKeepsItsFlagEvenWithTheRightReason() throws {
    let (store, context, _) = try makeStore()
    let row = insertMailRow(into: context)
    row.mergedCount = 2
    try context.save()

    try store.setAccount(row.id, to: UUID())

    XCTAssertNotNil(row.accountID)
    XCTAssertTrue(
      row.needsReview,
      "a second SourceRef means the pipeline flagged it again after insert")
  }

  /// A row the pipeline flagged with no insert-time reason at all — a near
  /// merge, an account conflict. `nil` is not `.unidentifiedAccount`.
  func testARowWithNoReasonKeepsItsFlag() throws {
    let (store, context, _) = try makeStore()
    let row = insertMailRow(into: context, reason: nil)

    try store.setAccount(row.id, to: UUID())

    XCTAssertNotNil(row.accountID)
    XCTAssertTrue(row.needsReview)
  }

  // MARK: - The loop closes: a later ingest resolves on its own

  /// What the unit is for. Assign an account on one row, then ask the real
  /// resolver — the one wired into the extractor — and it answers.
  func testAfterOneAssignmentTheRealResolverAnswers() throws {
    let (store, context, container) = try makeStoreAndContainer()
    let account = UUID()

    let resolver = SwiftDataAccountBindings(container: container)
    XCTAssertNil(
      resolver.accountID(senderDomain: domain, cardFragment: fragment),
      "nothing learned yet")

    let row = insertMailRow(into: context)
    try store.setAccount(row.id, to: account)

    XCTAssertEqual(resolver.accountID(senderDomain: domain, cardFragment: fragment), account)
    XCTAssertEqual(
      resolver.accountID(senderDomain: "ALERTS.HDFCBank.NET", cardFragment: "XX4471"),
      account,
      "the key is normalised on both sides")
    XCTAssertNil(
      resolver.accountID(senderDomain: domain, cardFragment: "8812"),
      "a different card is not this account")
    XCTAssertNil(resolver.accountID(senderDomain: domain, cardFragment: ""))
  }

  /// End to end through the extractor: a message from the same sender and card
  /// arrives already assigned and unflagged, with no second prompt.
  func testAFreshExtractorResolvesTheSameFixtureOnceTheBindingExists() throws {
    let (store, context, container) = try makeStoreAndContainer()
    let account = UUID()
    let resolver = SwiftDataAccountBindings(container: container)

    let message = try Self.hdfcFixtureMessage()
    let before = try XCTUnwrap(
      MailTransactionExtractor(bindings: resolver).extract(message))
    XCTAssertNil(before.accountID)
    XCTAssertTrue(before.needsReview)
    XCTAssertEqual(before.needsReviewReason, .unidentifiedAccount)

    // The row the user taps carries exactly what the extractor stamped, which
    // is the point: the binding is written under the key the next extraction
    // will look up.
    let row = insertMailRow(
      into: context,
      senderDomain: before.senderDomain,
      cardFragment: before.cardFragment)
    try store.setAccount(row.id, to: account)

    let after = try XCTUnwrap(
      MailTransactionExtractor(bindings: resolver).extract(message))
    XCTAssertEqual(after.accountID, account, "the same mail now knows its account")
    XCTAssertFalse(after.needsReview)
    XCTAssertNil(after.needsReviewReason)
  }

  /// R5: CloudKit forbids unique constraints, so two devices can each write a
  /// binding for one key. Both are updated on a re-assign, and the resolver
  /// picks the same one on every device.
  func testDuplicateBindingsConvergeRatherThanDivergePerDevice() throws {
    let (store, context, container) = try makeStoreAndContainer()
    let stale = UUID()
    context.insert(AccountBinding(senderDomain: domain, cardFragment: fragment, accountID: stale))
    context.insert(AccountBinding(senderDomain: domain, cardFragment: fragment, accountID: stale))
    try context.save()

    let account = UUID()
    let row = insertMailRow(into: context)
    try store.setAccount(row.id, to: account)

    let bindings = try context.fetch(FetchDescriptor<AccountBinding>())
    XCTAssertEqual(bindings.count, 2, "no row is deleted")
    XCTAssertEqual(Set(bindings.map(\.accountID)), [account], "every duplicate is updated")
    XCTAssertEqual(
      SwiftDataAccountBindings(container: container)
        .accountID(senderDomain: domain, cardFragment: fragment),
      account)
  }

  // MARK: -

  /// NomiIngest's own HDFC fixture, read off disk by relative path.
  ///
  /// Hand-building a `MailMessage` here would prove nothing: whether Layer 1
  /// matches depends on the pack entry's regexes, so a message written to suit
  /// this test would be a message written to pass it. `#filePath`-relative is
  /// how both fixture directories in this repo are already read — U0 froze the
  /// `Package.swift` files with no `resources:` declaration — and a moved
  /// fixture fails here loudly rather than silently.
  private static func hdfcFixtureMessage() throws -> MailMessage {
    let packages = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // NomiAppTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // NomiApp
      .deletingLastPathComponent()  // Packages
    let url = packages.appendingPathComponent(
      "NomiIngest/Tests/NomiIngestTests/Fixtures/Mail/hdfc_debit_netbanking.eml")
    return try RFC822Message.parse(try Data(contentsOf: url), uid: 7701, uidValidity: 900_100)
  }

  @discardableResult
  private func insertMailRow(
    into context: ModelContext,
    senderDomain: String? = "alerts.hdfcbank.net",
    cardFragment: String? = "4471",
    accountID: UUID? = nil,
    needsReview: Bool = true,
    reason: NeedsReviewReason? = .unidentifiedAccount
  ) -> Transaction {
    let row = Transaction(
      date: Date(timeIntervalSince1970: 1_787_000_000),
      descriptionText: "UPI-SWIGGY-swiggy@okhdfcbank",
      amountMinor: 45_900,
      accountID: accountID,
      sourceRaw: IngestSource.email.rawValue,
      needsReview: needsReview,
      senderDomain: senderDomain,
      cardFragment: cardFragment,
      needsReviewReasonRaw: reason?.rawValue)
    context.insert(row)
    try? context.save()
    return row
  }

  private func makeStore() throws -> (SwiftDataTransactionStore, ModelContext, ModelContainer) {
    try makeStoreAndContainer()
  }

  private func makeStoreAndContainer() throws
    -> (SwiftDataTransactionStore, ModelContext, ModelContainer)
  {
    let schema = Schema([
      Transaction.self, NomiCore.Category.self, Budget.self, BudgetAlertLog.self,
      Rule.self, Account.self, AccountBinding.self, ColumnMappingRecord.self,
    ])
    let container = try ModelContainer(
      for: schema,
      configurations: [
        ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
      ])
    let context = container.mainContext
    let store = SwiftDataTransactionStore(
      context: context,
      coordinator: WriteCoordinator(cache: InsightsCache()))
    return (store, context, container)
  }
}
