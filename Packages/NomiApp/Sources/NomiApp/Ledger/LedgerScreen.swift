import NomiCore
import NomiUI
import SwiftData
import SwiftUI

/// The Ledger tab.
///
/// **No unit ever owned this screen.** §2.18 caught three things missing from
/// U8's block; this is a fourth. `NomiUI` has `TransactionRow` (U5) and
/// `RecentTransactionsCard` (U9, five rows, dashboard-scoped) and no list
/// screen, while the tab bar and the acceptance criterion both require one
/// ("the transaction list renders against the real store"). It is built here on
/// §2.18's own reasoning for the tab bar: legal inside `NomiApp/**`, collides
/// with nobody, and reopening a merged unit to add it would cost more.
///
/// It is composed from `NomiUI`'s public pieces — `TransactionRow`, the design
/// tokens, the formatters — and defines no colours, spacings or type of its
/// own. `Design/**` is frozen and this screen reads it like every other.
///
/// **Scope, stated so it is not mistaken for the finished screen.** The design's
/// Ledger paragraph also specifies full-pill glass filter chips and a
/// category-hue magnitude bar under each row. Neither is here: those are
/// `NomiUI` craft, they are not in this unit's acceptance criteria, and half of
/// them built by a backend unit against a frozen token file is worse than none.
/// What is here is the structure — day sections, sticky headers with the day's
/// spend, rows through `TransactionRow`.
public struct LedgerScreen: View {
  private let insightsStore: any InsightsStore

  @Query(sort: \NomiCore.Category.sortIndex) private var categories: [NomiCore.Category]
  @Query(sort: \NomiCore.Account.displayName) private var accounts: [NomiCore.Account]

  /// Reading `generation` is what redraws this screen after a background sync.
  /// It holds no `@Query` over `Transaction` — the rows come from
  /// `InsightsStore`, so that it is the same cached, period-scoped path every
  /// other aggregate uses (R14) rather than a second unbounded fetch.
  @ObservedObject private var cache: InsightsCache

  public init(insightsStore: any InsightsStore, cache: InsightsCache) {
    self.insightsStore = insightsStore
    self.cache = cache
  }

  private var sections: [LedgerDaySection<NomiCore.Transaction>] {
    _ = cache.generation
    let rows = (try? insightsStore.transactions(in: .allTime)) ?? []
    return LedgerGrouping.days(rows)
  }

  private var categoryNames: [UUID: String] {
    Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
  }

  private var accountNames: [UUID: String] {
    Dictionary(accounts.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
  }

  public var body: some View {
    Group {
      if sections.isEmpty {
        emptyState
      } else {
        list
      }
    }
    .background(NomiColor.surfaceCanvas)
    .navigationTitle("Ledger")
  }

  private var list: some View {
    List {
      ForEach(sections) { section in
        Section {
          ForEach(section.rows) { transaction in
            TransactionRow(
              transaction: transaction,
              categoryName: transaction.categoryID.flatMap { categoryNames[$0] },
              accountName: transaction.accountID.flatMap { accountNames[$0] }
            )
            // The design's Ledger paragraph asks for `#1C1C1C` here, and
            // `Design/**` has no token for it — U5 shipped `surfaceCanvas`,
            // `surface` and `surfaceRaised` and no row surface. U5's rule is
            // that a missing token is an escalation and never something a later
            // unit adds quietly, so this uses the nearest existing token rather
            // than hard-coding a second `#1C1C1C` outside the frozen file.
            // Raised in this unit's PR; it is a one-line change in `NomiColor`
            // and the design already lists `#212121` vs `#1C1C1C` as a call only
            // a physical display can settle.
            .listRowBackground(NomiColor.surfaceRaised)
          }
        } header: {
          header(for: section)
        }
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
  }

  private func header(for section: LedgerDaySection<NomiCore.Transaction>) -> some View {
    HStack {
      Text(NomiFormatters.dayMonthYear.string(from: section.id))
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.textTertiary)
      Spacer()
      Text(NomiFormatters.amountString(minor: section.spentMinor))
        .font(TabularFigures.font(name: NomiFont.montserratMedium, size: 13))
        .foregroundStyle(NomiColor.textTertiary)
    }
  }

  private var emptyState: some View {
    VStack(spacing: NomiSpacing.sm) {
      Text("No transactions yet")
        .nomiTextStyle(.title)
        .foregroundStyle(NomiColor.textPrimary)
      Text("Connect your mail or import a statement to get started.")
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.textTertiary)
        .multilineTextAlignment(.center)
    }
    .padding(NomiSpacing.screenGutter)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
