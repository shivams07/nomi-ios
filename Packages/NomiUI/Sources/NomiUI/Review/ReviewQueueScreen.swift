import NomiCore
import SwiftData
import SwiftUI

/// The Review queue (S4, I-15). One flagged or uncategorised row at a time: the reason,
/// the amount, what the bank said, a 2x2 grid of category tiles, and "Remember for this
/// merchant". Full screen, presented from Home (`nomiOpenReview`). The initializer is
/// final.
///
/// Reads the category and account lists through `@Query` (the read/write asymmetry
/// rule). Every write goes through `ReviewQueueModel`, which goes through the stores.
public struct ReviewQueueScreen: View {
  public let transactionStore: TransactionStore
  public let insightsStore: InsightsStore
  public let categoryStore: CategoryStore
  public let ruleStore: RuleStore
  public let accountStore: AccountStore
  public let editor: TransactionEditing
  public let suggester: (any CategorySuggesting)?
  public let onClose: () -> Void

  @State private var model: ReviewQueueModel
  @State private var isConfirmingDelete = false
  @State private var isChoosingCategory = false
  @State private var isChoosingAccount = false

  @Query(sort: \NomiCore.Category.sortIndex) private var categories: [NomiCore.Category]
  @Query(sort: \NomiCore.Account.displayName) private var accounts: [NomiCore.Account]
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.modelContext) private var modelContext

  public init(
    transactionStore: TransactionStore,
    insightsStore: InsightsStore,
    categoryStore: CategoryStore,
    ruleStore: RuleStore,
    accountStore: AccountStore,
    editor: TransactionEditing,
    suggester: (any CategorySuggesting)?,
    onClose: @escaping () -> Void
  ) {
    self.transactionStore = transactionStore
    self.insightsStore = insightsStore
    self.categoryStore = categoryStore
    self.ruleStore = ruleStore
    self.accountStore = accountStore
    self.editor = editor
    self.suggester = suggester
    self.onClose = onClose
    _model = State(
      initialValue: ReviewQueueModel(
        transactionStore: transactionStore,
        insightsStore: insightsStore,
        ruleStore: ruleStore,
        suggester: suggester))
  }

  public var body: some View {
    Group {
      if !model.isLoaded {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if model.loadFailed {
        VStack(spacing: 0) {
          topBar(showsProgress: false)
          NomiLoadFailedCard { model.load() }
            .padding(.horizontal, NomiSpacing.screenGutter)
          Spacer(minLength: 0)
        }
      } else if let row = model.current {
        queue(row)
      } else {
        VStack(spacing: 0) {
          topBar(showsProgress: false)
          Spacer(minLength: 0)
          NomiEmptyState(
            systemImage: "checkmark.circle",
            title: "All caught up",
            message: "New alerts that need a look will show up here.",
            actionTitle: "Done",
            action: onClose
          )
          .padding(.horizontal, NomiSpacing.screenGutter)
          Spacer(minLength: 0)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(NomiColor.ground)
    .task {
      // The stored rules, read fresh at each rule decision. The store has no read
      // method, so this reads the same `Rule` rows S3a's Detail reads.
      let context = modelContext
      model.existingRules = {
        try context.fetch(FetchDescriptor<NomiCore.Rule>()).map {
          ReviewQueueRule(pattern: $0.pattern, categoryID: $0.categoryID, isEnabled: $0.isEnabled)
        }
      }
      model.load()
    }
    .alert("Delete this payment?", isPresented: $isConfirmingDelete) {
      Button("Keep", role: .cancel) {}
      Button("Delete", role: .destructive) { model.notATransaction() }
    } message: {
      Text("It will be removed from every total.")
    }
    .sheet(isPresented: $isChoosingCategory) {
      CategoryPickerSheet(categoryStore: categoryStore, selection: categorySelection)
    }
    .sheet(isPresented: $isChoosingAccount) {
      AccountPickerSheet(accountStore: accountStore, selection: model.accountID) { accountID in
        model.assignAccount(accountID)
      }
    }
  }

  // MARK: - Layout

  /// Close on the left, the "i of n" count in the middle, Skip on the right. Only the
  /// queue shows the count and Skip; the empty and failed states show Close alone.
  private func topBar(showsProgress: Bool) -> some View {
    HStack(spacing: NomiSpacing.xs) {
      Button {
        onClose()
      } label: {
        Image(systemName: "xmark")
          .resizable()
          .scaledToFit()
          .frame(width: 16, height: 16)
          .foregroundStyle(NomiColor.navy)
          .frame(width: NomiSpacing.minTarget, height: NomiSpacing.minTarget)
          .background(Circle().fill(NomiColor.secondaryFill))
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text("Close review"))

      Text(showsProgress ? model.progress : "")
        .nomiTextStyle(.headline)
        .foregroundStyle(NomiColor.ink)
        .frame(maxWidth: .infinity)

      Group {
        if showsProgress {
          Button("Skip") { model.skip() }
            .buttonStyle(.plain)
            .nomiTextStyle(.navAction)
            .foregroundStyle(NomiColor.navy)
        } else {
          Color.clear
        }
      }
      .frame(minWidth: NomiSpacing.minTarget, alignment: .trailing)
    }
    .padding(.horizontal, NomiSpacing.screenGutter)
    .padding(.top, NomiSpacing.xs)
    .padding(.bottom, NomiSpacing.xxs)
  }

  private func queue(_ row: NomiCore.Transaction) -> some View {
    VStack(spacing: 0) {
      topBar(showsProgress: true)
      NomiProgressBar(fraction: model.progressFraction, state: .under, height: 6)
        .padding(.horizontal, NomiSpacing.screenGutter)
        .padding(.bottom, NomiSpacing.xs)
      ScrollView {
        VStack(spacing: NomiSpacing.cardGap) {
          itemCard(row)
          choiceSection
          if model.showsAccountRow {
            accountRow
          }
          if model.rememberPattern != nil {
            rememberRow
          }
        }
        .padding(.horizontal, NomiSpacing.screenGutter)
        .padding(.vertical, NomiSpacing.xs)
      }
      footer
    }
  }

  private var footer: some View {
    VStack(spacing: NomiSpacing.xs) {
      if let message = model.errorMessage {
        NomiStatusNote(message, tone: .error, systemImage: "exclamationmark.circle")
      }
      Button("Confirm, next") {
        model.confirmNext()
      }
      .buttonStyle(NomiPrimaryButtonStyle())
      .disabled(!model.canConfirm)

      Button {
        isConfirmingDelete = true
      } label: {
        Text("Not a transaction")
          .nomiTextStyle(.button)
          .foregroundStyle(NomiColor.error)
          .frame(maxWidth: .infinity, minHeight: NomiSpacing.minTarget)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, NomiSpacing.screenGutter)
    .padding(.vertical, NomiSpacing.sm)
  }

  // MARK: - The row

  private func itemCard(_ row: NomiCore.Transaction) -> some View {
    VStack(spacing: NomiSpacing.xs) {
      NomiTag(ReviewQueueLogic.reasonText(for: row), tone: .warning)

      Text(
        TransactionRow.title(
          merchantName: row.merchantName, descriptionText: row.descriptionText, categoryName: nil)
      )
      .nomiTextStyle(.headline)
      .foregroundStyle(NomiColor.ink)
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)

      amountLine(row)

      Text(
        ReviewQueueLogic.caption(
          for: row, accountName: accountName(for: row), now: Date(), calendar: .current)
      )
      .nomiTextStyle(.caption)
      .foregroundStyle(NomiColor.inkSecondary)
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)

      if !row.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Text("\"\(row.descriptionText)\"")
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.inkSecondary)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(NomiSpacing.sm)
          .background(
            RoundedRectangle(cornerRadius: NomiRadius.inset, style: .continuous)
              .fill(NomiColor.secondaryFill)
          )
          .padding(.top, NomiSpacing.xxs)
      }
    }
    .frame(maxWidth: .infinity)
    .nomiCard(
      padding: EdgeInsets(
        top: NomiSpacing.md, leading: NomiSpacing.sm, bottom: NomiSpacing.md, trailing: NomiSpacing.sm))
  }

  /// The amount at the hero size, signed by direction, the decimals dimmed. Typeset as
  /// Detail's sheet amount is (`TransactionDetailScreen.amountLine`).
  private func amountLine(_ row: NomiCore.Transaction) -> some View {
    let isCredit = row.direction == .credit
    let signed = TransactionDetailLogic.signedMinor(amountMinor: row.amountMinor, direction: row.direction)
    let parts = NomiAmountFormat.parts(minor: signed, currencyCode: row.currencyCode, showPlus: isCredit)
    let color = isCredit ? NomiColor.navy : NomiColor.ink
    let spoken = (isCredit ? "Credit, " : "Debit, ") + parts.sign + parts.integer + parts.decimals
    return (Text(parts.sign + parts.integer).foregroundStyle(color)
      + Text(parts.decimals).foregroundStyle(color.opacity(NomiColor.decimalOpacityGround)))
      .font(NomiTextStyle.heroAmount.font)
      .lineLimit(1)
      .minimumScaleFactor(0.5)
      .accessibilityLabel(Text(spoken))
  }

  private func accountName(for row: NomiCore.Transaction) -> String? {
    guard let accountID = row.accountID else { return nil }
    return accounts.first(where: { $0.id == accountID })?.displayName
  }

  // MARK: - Category tiles

  private var choiceSection: some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xs) {
      Text("What was this?")
        .nomiTextStyle(.label)
        .foregroundStyle(NomiColor.inkSecondary)
        .padding(.leading, NomiSpacing.xxs)
      // One column at accessibility sizes: a two-column tile is too narrow for a single
      // long word, which then breaks mid-word. Full-width tiles keep each label whole.
      LazyVGrid(columns: tileColumns, spacing: NomiSpacing.xs) {
        ForEach(model.choices, id: \.self) { choice in
          tile(choice)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var tileColumns: [GridItem] {
    let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
    return Array(repeating: GridItem(.flexible(), spacing: NomiSpacing.xs, alignment: .top), count: count)
  }

  private func tile(_ choice: ReviewQueueModel.Choice) -> some View {
    let content = tileContent(for: choice)
    return Button {
      switch choice {
      case .category(let id):
        model.selectedCategoryID = id
      case .allCategories:
        isChoosingCategory = true
      }
    } label: {
      tileLabel(content)
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(content.isSelected ? .isSelected : [])
  }

  private struct TileContent {
    let name: String
    let symbolName: String
    let subtitle: String?
    let isSelected: Bool
  }

  private func tileContent(for choice: ReviewQueueModel.Choice) -> TileContent {
    switch choice {
    case .category(let id):
      let category = categories.first(where: { $0.id == id })
      return TileContent(
        name: category?.name ?? String(localized: "Uncategorized", bundle: .module),
        symbolName: category?.symbolName ?? "questionmark",
        subtitle: id == model.bestGuessID ? String(localized: "Best guess", bundle: .module) : nil,
        isSelected: model.selectedCategoryID == id)
    case .allCategories:
      // The picker can choose a category the tiles do not show. That choice is named
      // on the "All categories" tile, which is then the selected one.
      var pickedName: String?
      var isPickedOutsideTiles = false
      if let picked = model.selectedCategoryID, !model.choices.contains(.category(picked)) {
        isPickedOutsideTiles = true
        pickedName = categories.first(where: { $0.id == picked })?.name
      }
      return TileContent(
        name: String(localized: "All categories", bundle: .module),
        symbolName: "ellipsis",
        subtitle: pickedName,
        isSelected: isPickedOutsideTiles)
    }
  }

  private func tileLabel(_ content: TileContent) -> some View {
    let single = ReviewQueueLogic.isSingleWord(content.name)
    let ink = content.isSelected ? NomiColor.onPrimary : NomiColor.ink
    return
      HStack(alignment: .center, spacing: NomiSpacing.xs) {
        Image(systemName: content.symbolName)
          .resizable()
          .scaledToFit()
          .frame(width: 18, height: 18)
          .foregroundStyle(content.isSelected ? NomiColor.onPrimary : NomiColor.iconGlyph)
          .frame(width: 36, height: 36)
          .background(
            Circle().fill(content.isSelected ? NomiColor.onPrimary.opacity(0.16) : NomiColor.iconTile)
          )
          .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
          Text(content.name)
            .nomiTextStyle(.button)
            .foregroundStyle(ink)
            .multilineTextAlignment(.leading)
            .lineLimit(single ? 1 : nil)
            .minimumScaleFactor(single ? 0.6 : 1)
            .fixedSize(horizontal: false, vertical: true)
          if let subtitle = content.subtitle {
            Text(subtitle)
              .nomiTextStyle(.footnote)
              .foregroundStyle(content.isSelected ? NomiColor.onPrimary.opacity(0.8) : NomiColor.inkSecondary)
              .multilineTextAlignment(.leading)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(NomiSpacing.xs + NomiSpacing.xxs)
      .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: NomiRadius.inset, style: .continuous)
          .fill(content.isSelected ? NomiColor.primary : NomiColor.card)
      )
      .overlay(
        RoundedRectangle(cornerRadius: NomiRadius.inset, style: .continuous)
          .strokeBorder(content.isSelected ? Color.clear : NomiColor.separator, lineWidth: 1)
      )
      .contentShape(RoundedRectangle(cornerRadius: NomiRadius.inset, style: .continuous))
  }

  // MARK: - Account and remember

  private var accountRow: some View {
    Button {
      isChoosingAccount = true
    } label: {
      HStack(alignment: .center, spacing: NomiSpacing.xs) {
        Text("Account")
          .nomiTextStyle(.rowTitle)
          .foregroundStyle(NomiColor.ink)
        Spacer(minLength: NomiSpacing.xs)
        Text(accountLabel)
          .nomiTextStyle(.rowBody)
          .foregroundStyle(NomiColor.inkSecondary)
          .multilineTextAlignment(.trailing)
          .fixedSize(horizontal: false, vertical: true)
        Image(systemName: "chevron.right")
          .resizable()
          .scaledToFit()
          .frame(width: 12, height: 12)
          .foregroundStyle(NomiColor.inkSecondary)
          .accessibilityHidden(true)
      }
      .frame(minHeight: NomiSpacing.rowMinHeight)
      .padding(.horizontal, NomiSpacing.sm)
      .frame(maxWidth: .infinity)
      .contentShape(Rectangle())
      .nomiCard(padding: EdgeInsets())
    }
    .buttonStyle(.plain)
  }

  private var accountLabel: String {
    let fallback = String(localized: "Choose an account", bundle: .module)
    guard let accountID = model.accountID else { return fallback }
    return accounts.first(where: { $0.id == accountID })?.displayName ?? fallback
  }

  private var rememberRow: some View {
    NomiToggleRow(
      title: "Remember for this merchant",
      caption: "Future payments skip this queue",
      isOn: rememberBinding
    )
    .padding(.horizontal, NomiSpacing.sm)
    .padding(.vertical, NomiSpacing.xxs)
    .frame(maxWidth: .infinity)
    .nomiCard(padding: EdgeInsets())
  }

  // MARK: - Bindings

  private var categorySelection: Binding<UUID?> {
    Binding(
      get: { model.selectedCategoryID },
      set: { model.selectedCategoryID = $0 })
  }

  private var rememberBinding: Binding<Bool> {
    Binding(
      get: { model.remember },
      set: { model.remember = $0 })
  }
}
