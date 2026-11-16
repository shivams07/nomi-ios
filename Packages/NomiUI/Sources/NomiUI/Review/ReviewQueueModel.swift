import Foundation
import NomiCore
import Observation

/// The Review queue's read and writes (S4 steps 2 and 3), outside the view so plain
/// XCTest can drive it with spies. `load()` reads the flagged rows and this month's
/// uncategorised rows once, into a snapshot. Each action writes through a store and
/// then moves to the next row. A failed write keeps the row on screen and says so.
///
/// Every write goes through the store, and the store owns the consequences (a
/// category write stamps the row as the user's, a delete unpairs a transfer partner,
/// an account write may clear a flag). The model only decides which writes to make.
@Observable @MainActor final class ReviewQueueModel {
  /// One tile on the grid: a category, or the "All categories" picker.
  enum Choice: Hashable {
    case category(UUID)
    case allCategories
  }

  @ObservationIgnored private let transactionStore: TransactionStore
  @ObservationIgnored private let insightsStore: InsightsStore
  @ObservationIgnored private let ruleStore: RuleStore
  @ObservationIgnored private let suggester: (any CategorySuggesting)?
  @ObservationIgnored private let now: () -> Date
  @ObservationIgnored private let calendar: Calendar

  /// The snapshot, in queue order. A row keeps its place after a write, so the
  /// progress count only moves when the user moves on.
  private(set) var items: [NomiCore.Transaction] = []
  private(set) var index = 0
  private(set) var isLoaded = false
  /// The queue could not be read. Distinct from an empty queue, which is finished.
  private(set) var loadFailed = false
  /// Set by a failed write; cleared by the next row or the next successful write.
  private(set) var errorMessage: String?
  /// The category the app thinks this row belongs to: the suggestion when there is
  /// one, else the row's own category. Shown as the "Best guess" tile.
  private(set) var bestGuessID: UUID?
  private(set) var choices: [Choice] = []
  /// The current row's account, kept here so the account row redraws after a write.
  private(set) var accountID: UUID?
  /// The trailing three months' categories, read once per load. Empty when the read failed.
  private var history: [CategorySlice] = []
  var selectedCategoryID: UUID?
  var remember = false

  init(
    transactionStore: TransactionStore,
    insightsStore: InsightsStore,
    ruleStore: RuleStore,
    suggester: (any CategorySuggesting)?,
    now: @escaping () -> Date = { Date() },
    calendar: Calendar = NomiCalendar.india
  ) {
    self.transactionStore = transactionStore
    self.insightsStore = insightsStore
    self.ruleStore = ruleStore
    self.suggester = suggester
    self.now = now
    self.calendar = calendar
  }

  // MARK: - What the screen shows

  var current: NomiCore.Transaction? {
    items.indices.contains(index) ? items[index] : nil
  }

  /// Loaded, readable, and nothing left to show.
  var isFinished: Bool {
    isLoaded && !loadFailed && current == nil
  }

  /// "<i> of <n>", counted from one. Empty when there is no current row.
  var progress: String {
    guard current != nil else { return "" }
    return "\(index + 1) of \(items.count)"
  }

  /// The share of the queue reached, including the current row.
  var progressFraction: Double {
    guard !items.isEmpty else { return 0 }
    return min(Double(index + 1), Double(items.count)) / Double(items.count)
  }

  /// Confirm needs a row and a category. Without a best guess the user picks one first.
  var canConfirm: Bool {
    current != nil && selectedCategoryID != nil
  }

  /// The rule "Remember" would write, or nil when the row names no merchant.
  var rememberPattern: String? {
    guard let row = current else { return nil }
    return MerchantRulePattern.pattern(
      merchantName: row.merchantName, normalizedDescription: row.normalizedDescription)
  }

  /// The account row shows for a row the pipeline could not tie to an account.
  var showsAccountRow: Bool {
    current?.needsReviewReason == .unidentifiedAccount
  }

  // MARK: - Actions

  /// Reads the queue and this month's rows, and shows the first row. A read failure
  /// leaves the snapshot empty and sets `loadFailed`.
  func load() {
    do {
      let flagged = try transactionStore.reviewQueue()
      let parts = calendar.dateComponents([.year, .month], from: now())
      let monthRows = try insightsStore.transactions(
        in: .month(year: parts.year ?? 0, month: parts.month ?? 0))
      items = ReviewQueueLogic.items(
        flagged: flagged, monthRows: monthRows, now: now(), calendar: calendar)
      loadFailed = false
    } catch {
      items = []
      loadFailed = true
    }
    index = 0
    history = (try? insightsStore.insights(for: .trailingMonths(3)).byCategory) ?? []
    isLoaded = true
    prepareCurrent()
  }

  /// Writes the category if it changed, then the rule if "Remember" is on and no rule
  /// already files this merchant under that category, then clears the flag if the row
  /// had one. Advances only when every write before it succeeded.
  func confirmNext() {
    guard let row = current, let categoryID = selectedCategoryID else { return }
    do {
      // Judged before any write: the first write stamps the row as the user's, and
      // a suggestion for a manual row is nil.
      let alreadyFiled = ruleAlreadyFiles(row, categoryID: categoryID)
      if row.categoryID != categoryID {
        try transactionStore.setCategory(row.id, to: categoryID)
      }
      if remember, !alreadyFiled, let pattern = rememberPattern {
        try ruleStore.create(pattern: pattern, categoryID: categoryID)
      }
      if row.needsReview {
        try transactionStore.dismissReview(row.id)
      }
      advance()
    } catch {
      errorMessage = Self.saveFailed
    }
  }

  /// Moves on without a write.
  func skip() {
    advance()
  }

  /// Deletes the current row. The screen calls this only after the user confirms.
  func notATransaction() {
    guard let row = current else { return }
    do {
      try transactionStore.delete(row.id)
      advance()
    } catch {
      errorMessage = Self.saveFailed
    }
  }

  /// Assigns the current row's account (or clears it) and stays on the row.
  func assignAccount(_ accountID: UUID?) {
    guard let row = current else { return }
    do {
      try transactionStore.setAccount(row.id, to: accountID)
      self.accountID = accountID
      errorMessage = nil
    } catch {
      errorMessage = Self.saveFailed
    }
  }

  // MARK: - Private

  private static let saveFailed = "That didn't save. Try again."

  private func advance() {
    index += 1
    prepareCurrent()
  }

  /// Sets the tiles, the selection, the remember switch and the account for the
  /// current row. Reads the suggester once per row.
  private func prepareCurrent() {
    errorMessage = nil
    guard let row = current else {
      bestGuessID = nil
      choices = []
      selectedCategoryID = nil
      remember = false
      accountID = nil
      return
    }
    bestGuessID = suggestion(for: row)?.categoryID ?? row.categoryID
    let ids = ReviewQueueLogic.choiceIDs(bestGuess: bestGuessID, history: history)
    choices = ids.map { Choice.category($0) } + [.allCategories]
    selectedCategoryID = bestGuessID
    remember = rememberPattern != nil
    accountID = row.accountID
  }

  /// The suggester's answer, or nil. A read that fails leaves the suggestion out: it
  /// is an aid, and the queue still works without it.
  private func suggestion(for row: NomiCore.Transaction) -> CategorySuggestion? {
    do {
      return try suggester?.suggestion(for: row.id) ?? nil
    } catch {
      return nil
    }
  }

  /// True when a rule already files this merchant under `categoryID`, so "Remember"
  /// would only duplicate it. Two sources of evidence: the row was already filed by a
  /// rule under that category, or the suggester names a rule for that category.
  ///
  /// Known gap: the suggester consults history before rules, so when history answers
  /// first, a system rule that files the merchant under the same category is not seen
  /// here, and a user rule is written. `RuleStore` has no read method to close that.
  private func ruleAlreadyFiles(_ row: NomiCore.Transaction, categoryID: UUID) -> Bool {
    if row.categorySource == .rule, row.appliedRuleID != nil, row.categoryID == categoryID {
      return true
    }
    guard let suggestion = suggestion(for: row) else { return false }
    guard case .rule = suggestion.reason else { return false }
    return suggestion.categoryID == categoryID
  }
}
