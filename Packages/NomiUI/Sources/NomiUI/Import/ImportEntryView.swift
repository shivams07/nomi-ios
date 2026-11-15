import NomiCore
import NomiPreview
import SwiftData
import SwiftUI

/// The file picker, the "Check before importing" screen (S11), the column-mapping
/// sheet, the rows-not-read sheet and the result screen (U7; IM). H0 "Import from
/// file" in the native large-title bar, "Check before importing" once a file is
/// counted. The one primary action on each screen is pinned to the bottom edge.
/// Light only.
public struct ImportEntryView: View {
  public let fileImportService: FileImportService

  @Query(sort: \NomiCore.Account.displayName) private var accounts: [NomiCore.Account]
  @Environment(\.dismiss) private var dismiss
  /// The "show the Ledger" action (FU-1). `nil` until RootView sets it, and the
  /// Done state's "View in Ledger" is hidden while it is nil.
  @Environment(\.nomiShowLedger) private var showLedger
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  /// The file under check. Nil on the picker, before a file is chosen.
  @State private var check: ImportCheckModel?
  @State private var isPickerPresented = false
  @State private var isMappingPresented = false
  @State private var isAccountPresented = false
  @State private var isUnreadablePresented = false
  @State private var selectedAccountID: UUID?

  public init(fileImportService: FileImportService) {
    self.fileImportService = fileImportService
  }

  /// Preview-only entry point. Starts on a seeded check, so canvases can render
  /// each state without a real file pick.
  init(fileImportService: FileImportService, initialCheck: ImportCheckModel) {
    self.fileImportService = fileImportService
    _check = State(initialValue: initialCheck)
  }

  public var body: some View {
    content
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(NomiColor.ground)
      .navigationTitle(navigationTitle)
      #if os(iOS)
      // The check screen's title is inline: a large title truncates "Check before importing" at 390 pt.
      .navigationBarTitleDisplayMode(isChecking ? .inline : .large)
      #endif
      .fileImporter(
        isPresented: $isPickerPresented,
        allowedContentTypes: ImportFileTypes.allowed
      ) { result in
        if case .success(let url) = result {
          startCheck(url)
        }
      }
      .sheet(isPresented: $isMappingPresented) {
        if let model = check, let preview = model.inspected, let current = model.mapping {
          ColumnMappingEditor(headers: preview.headers, mapping: mappingBinding(model, current: current))
        }
      }
      .sheet(isPresented: $isAccountPresented) {
        AccountPickerSheet(accountStore: nil, selection: selectedAccountID, onSelect: { selectedAccountID = $0 })
      }
      .sheet(isPresented: $isUnreadablePresented) {
        UnreadableRowsSheet(rows: unreadableRows)
      }
  }

  @ViewBuilder
  private var content: some View {
    if let model = check {
      switch model.state {
      case .loading:
        inspectingView
      case .needsColumns(let preview):
        needsColumnsView(model, preview)
      case .ready(let preview, let dry, _):
        readyView(model, preview, dry)
      case .importing:
        importingView
      case .failed(let message):
        failedView(model, message)
      case .done(let summary):
        doneView(summary)
      }
    } else {
      idleView
    }
  }

  /// True on the check screen (needs columns, ready, importing). Those states use an inline title.
  private var isChecking: Bool {
    switch check?.state {
    case .needsColumns?, .ready?, .importing?:
      return true
    default:
      return false
    }
  }

  private var navigationTitle: String {
    isChecking
      ? String(localized: "Check before importing", bundle: .module)
      : String(localized: "Import from file", bundle: .module)
  }

  // MARK: - States

  private var idleView: some View {
    NomiEmptyState(
      systemImage: "arrow.up.doc",
      title: "Choose a file to import",
      message: "Use a CSV or statement export from your bank. Nomi shows a preview before it saves anything."
    )
    .padding(.horizontal, NomiSpacing.screenGutter)
    .padding(.top, 96)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .safeAreaInset(edge: .bottom) {
      pinnedPrimary(String(localized: "Choose file", bundle: .module)) { isPickerPresented = true }
    }
  }

  private var inspectingView: some View {
    VStack(spacing: NomiSpacing.xs) {
      ProgressView()
      Text("Reading file…")
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.inkSecondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityElement(children: .combine)
  }

  /// A format with no mapping, or a mapping that parses no rows. The column
  /// mapping sheet opens first, and "Fix columns" reopens it.
  private func needsColumnsView(_ model: ImportCheckModel, _ preview: ImportPreview) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: NomiSpacing.md) {
        stepCaption
        fileCard(model, subtitle: ImportLogic.fileSubtitle(bankLabel: preview.detectedBankLabel, sample: []))
        NomiStatusNote(
          String(localized: "Nomi doesn’t recognize this format yet. Match the columns to continue.", bundle: .module),
          tone: .warning,
          systemImage: "questionmark.circle"
        )
        Text(String(localized: "Nomi remembers the column mapping after an import succeeds.", bundle: .module))
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.inkSecondary)
          .padding(.horizontal, NomiSpacing.xxs)
      }
      .padding(.horizontal, NomiSpacing.screenGutter)
      .padding(.top, NomiSpacing.sm)
      .padding(.bottom, NomiSpacing.sm)
    }
    .safeAreaInset(edge: .bottom) {
      pinnedPrimary(String(localized: "Fix columns", bundle: .module)) { isMappingPresented = true }
    }
    .onAppear { isMappingPresented = true }
  }

  /// The check screen (`Import` artboard, "Check before importing"). The tiles, the
  /// note and the primary describe the dry run's counts under the mapping shown,
  /// and say what the commit does with each group.
  private func readyView(_ model: ImportCheckModel, _ preview: ImportPreview, _ dry: ImportDryRun) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        stepCaption
        fileCard(model, subtitle: ImportLogic.fileSubtitle(bankLabel: preview.detectedBankLabel, sample: dry.sample))
          .padding(.top, NomiSpacing.xs)
        countTiles(dry)
          .padding(.top, NomiSpacing.md)
        if dry.matchExistingCount > 0 {
          Text(ImportLogic.alreadyInNomiNote)
            .nomiTextStyle(.caption)
            .foregroundStyle(NomiColor.inkSecondary)
            .padding(.top, NomiSpacing.xs)
            .padding(.horizontal, NomiSpacing.xxs)
        }
        if let repeatNote = ImportLogic.repeatNote(for: dry) {
          NomiStatusNote(repeatNote, tone: .ok, systemImage: "arrow.triangle.2.circlepath")
            .padding(.top, NomiSpacing.xs)
        }
        accountRow
          .padding(.top, NomiSpacing.md)
        firstRowsHeader
        if !dry.sample.isEmpty {
          sampleRowsCard(dry.sample)
        }
        if let skipped = ImportLogic.couldNotReadNote(for: dry) {
          NomiStatusNote(
            skipped,
            tone: .warning,
            systemImage: "exclamationmark.circle",
            actionTitle: String(localized: "Show them", bundle: .module)
          ) {
            isUnreadablePresented = true
          }
          .padding(.top, NomiSpacing.md)
        }
        if let note = model.commitNote {
          NomiStatusNote(note, tone: .error, systemImage: "exclamationmark.circle")
            .padding(.top, NomiSpacing.md)
        }
      }
      .padding(.horizontal, NomiSpacing.screenGutter)
      .padding(.top, NomiSpacing.sm)
      .padding(.bottom, NomiSpacing.sm)
    }
    .safeAreaInset(edge: .bottom) {
      pinnedPrimary(
        ImportLogic.importTitle(createCount: dry.createCount),
        isEnabled: ImportLogic.canImport(createCount: dry.createCount) && !model.isCounting
      ) {
        Task { await model.importNow(accountID: selectedAccountID) }
      }
    }
  }

  /// Between the sheet's Save and a commit the screen only shows work in progress.
  private var importingView: some View {
    VStack(spacing: NomiSpacing.xs) {
      ProgressView()
      Text(String(localized: "Importing…", bundle: .module))
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.inkSecondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityElement(children: .combine)
  }

  /// The count could not be made (a file that cannot be inspected, a dry run that throws,
  /// or a lookup that fails). Try again repeats the step that failed.
  private func failedView(_ model: ImportCheckModel, _ message: String) -> some View {
    ScrollView {
      NomiLoadFailedCard(message: message) {
        Task { await model.retry() }
      }
      .padding(.horizontal, NomiSpacing.screenGutter)
      .padding(.top, NomiSpacing.sm)
      .padding(.bottom, NomiSpacing.sm)
    }
  }

  /// `ImportDone` artboard: the result card, then "View in Ledger" while the
  /// root has wired `\.nomiShowLedger`, then the pinned "Done". The title and
  /// detail copy are Claire's ruling and are unchanged here.
  @ViewBuilder
  private func doneView(_ summary: ImportSummary) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: NomiSpacing.sm) {
        HStack(alignment: .center, spacing: 12) {
          Image(systemName: "checkmark")
            .resizable()
            .scaledToFit()
            .frame(width: 18, height: 18)
            .foregroundStyle(NomiColor.navy)
            .frame(width: 40, height: 40)
            .background(Circle().fill(NomiColor.iconTile))
            .accessibilityHidden(true)

          VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
            let lines = ImportDoneCopy.lines(summary)
            if lines.isEmpty {
              Text(ImportDoneCopy.nothingAdded)
                .nomiTextStyle(.headline)
                .foregroundStyle(NomiColor.ink)
            }
            ForEach(lines.indices, id: \.self) { index in
              Text(lines[index])
                .nomiTextStyle(index == 0 ? .headline : .caption)
                .foregroundStyle(index == 0 ? NomiColor.ink : NomiColor.inkSecondary)
            }
            if let name = selectedAccountName {
              Text(name)
                .nomiTextStyle(.caption)
                .foregroundStyle(NomiColor.inkSecondary)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nomiCard(padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
        .accessibilityElement(children: .combine)
        if NomiShowLedgerLogic.showsControl(isWired: showLedger != nil), let showLedger {
          viewInLedgerCard(showLedger)
        }
      }
      .padding(.horizontal, NomiSpacing.screenGutter)
      .padding(.top, NomiSpacing.sm)
    }
    .safeAreaInset(edge: .bottom) {
      pinnedPrimary("Done") { dismiss() }
    }
  }

  /// The row link under the result card (`ImportDone` artboard): navy "View in
  /// Ledger" with a chevron, on a card. It clears Home's stack, which takes this
  /// screen with it, and selects the Ledger tab.
  private func viewInLedgerCard(_ showLedger: NomiShowLedgerAction) -> some View {
    Button {
      showLedger()
    } label: {
      HStack(spacing: NomiSpacing.xs) {
        Text("View in Ledger")
          .nomiTextStyle(.rowTitle)
          .foregroundStyle(NomiColor.navy)
        Spacer(minLength: NomiSpacing.xs)
        Image(systemName: "chevron.right")
          .resizable()
          .scaledToFit()
          .frame(width: 16, height: 16)
          .foregroundStyle(NomiColor.inkSecondary)
          .accessibilityHidden(true)
      }
      .frame(maxWidth: .infinity, minHeight: NomiSpacing.rowMinHeight)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity)
    .nomiCard()
  }

  // MARK: - Pieces

  /// The one primary action of a screen: a 52 pt black capsule pinned to the
  /// bottom edge. Disabled, it drops to 40% (`NomiPrimaryButtonStyle`).
  private func pinnedPrimary(
    _ title: String,
    isEnabled: Bool = true,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Text(title)
    }
    .buttonStyle(NomiPrimaryButtonStyle(height: 52))
    .disabled(!isEnabled)
    .padding(.horizontal, NomiSpacing.screenGutter)
    .padding(.top, NomiSpacing.xs)
    .padding(.bottom, NomiSpacing.xs)
    .frame(maxWidth: .infinity)
    .background(NomiColor.ground)
  }

  private var stepCaption: some View {
    HStack {
      Spacer(minLength: NomiSpacing.xs)
      Text(String(localized: "Step 2 of 2", bundle: .module))
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.inkSecondary)
    }
  }

  /// The file's icon, its name and the format and date range line, with the
  /// "Change file" pill that goes back to the picker.
  private func fileCard(_ model: ImportCheckModel, subtitle: String) -> some View {
    HStack(alignment: .center, spacing: NomiSpacing.xs) {
      Image(systemName: "doc.text")
        .resizable()
        .scaledToFit()
        .frame(width: 18, height: 18)
        .foregroundStyle(NomiColor.navy)
        .frame(width: 40, height: 40)
        .background(Circle().fill(NomiColor.iconTile))
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        Text(model.url.lastPathComponent)
          .nomiTextStyle(.rowTitle)
          .foregroundStyle(NomiColor.ink)
          .lineLimit(1)
        Text(subtitle)
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.inkSecondary)
          .lineLimit(2)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Button {
        isPickerPresented = true
      } label: {
        Text(String(localized: "Change file", bundle: .module))
          .nomiTextStyle(.label)
          .foregroundStyle(NomiColor.ink)
          .padding(.horizontal, 14)
          .frame(minHeight: NomiSpacing.minTarget)
          .background(Capsule().fill(NomiColor.card))
          .overlay(Capsule().strokeBorder(NomiColor.separator, lineWidth: 1))
          .contentShape(Capsule())
      }
      .buttonStyle(.plain)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .nomiCard(padding: EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
  }

  /// "new", "already in Nomi", "could not read". The last one is amber while it
  /// counts rows that will be skipped.
  /// Three columns, stacked into rows at accessibility sizes: a 390 pt screen leaves
  /// a column about 100 pt wide, too narrow for "already in Nomi" at AX3 without breaking words.
  private func countTiles(_ dry: ImportDryRun) -> some View {
    let layout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: NomiSpacing.xs))
      : AnyLayout(HStackLayout(alignment: .top, spacing: NomiSpacing.xs))
    return layout {
      countTile(dry.createCount, String(localized: "new", bundle: .module), tint: NomiColor.ink)
      countTile(dry.matchExistingCount, String(localized: "already in Nomi", bundle: .module), tint: NomiColor.ink)
      countTile(
        dry.unreadable.count,
        String(localized: "could not read", bundle: .module),
        tint: dry.unreadable.isEmpty ? NomiColor.ink : NomiColor.warning
      )
    }
  }

  private func countTile(_ value: Int, _ caption: String, tint: Color) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("\(value)")
        .nomiTextStyle(.amountLarge)
        .foregroundStyle(tint)
      Text(caption)
        .nomiTextStyle(.footnote)
        .foregroundStyle(NomiColor.inkSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .nomiCard(padding: EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
    .accessibilityElement(children: .combine)
  }

  /// "Import into": a card row that opens the account picker. "Unassigned" when none is chosen.
  private var accountRow: some View {
    Button {
      isAccountPresented = true
    } label: {
      HStack(spacing: NomiSpacing.xs) {
        VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
          Text(String(localized: "Import into", bundle: .module))
            .nomiTextStyle(.label)
            .foregroundStyle(NomiColor.inkSecondary)
          Text(selectedAccountLabel)
            .nomiTextStyle(.rowTitle)
            .foregroundStyle(NomiColor.ink)
        }
        Spacer(minLength: NomiSpacing.xs)
        Image(systemName: "chevron.right")
          .resizable()
          .scaledToFit()
          .frame(width: 14, height: 14)
          .foregroundStyle(NomiColor.inkSecondary)
          .accessibilityHidden(true)
      }
      .frame(maxWidth: .infinity, minHeight: NomiSpacing.rowMinHeight, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity)
    .nomiCard()
  }

  /// The section label, with "Fix columns" on the same line. It stays reachable when every row is unreadable.
  private var firstRowsHeader: some View {
    HStack(alignment: .center) {
      Text(String(localized: "First rows, as Nomi reads them", bundle: .module))
        .nomiTextStyle(.label)
        .foregroundStyle(NomiColor.inkDeep)
        .accessibilityAddTraits(.isHeader)
      Spacer(minLength: NomiSpacing.xs)
      Button {
        isMappingPresented = true
      } label: {
        Text(String(localized: "Fix columns", bundle: .module))
          .nomiTextStyle(.label)
          .foregroundStyle(NomiColor.navy)
          .frame(minHeight: NomiSpacing.minTarget)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
    .padding(.top, NomiSpacing.md)
    .padding(.bottom, NomiSpacing.xs)
    .padding(.horizontal, NomiSpacing.xxs)
  }

  private func sampleRowsCard(_ rows: [ImportDryRunRow]) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(rows) { row in
        if row.id != rows.first?.id {
          rowDivider
        }
        sampleRow(row)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .nomiCard()
  }

  /// One sample row: the narration as the title (merchant is not derived here), the
  /// date and narration as the subtitle, then the signed amount.
  private func sampleRow(_ row: ImportDryRunRow) -> some View {
    HStack(alignment: .center, spacing: NomiSpacing.xs) {
      VStack(alignment: .leading, spacing: 2) {
        Text(ImportLogic.sampleTitle(row))
          .nomiTextStyle(.rowTitle)
          .foregroundStyle(NomiColor.ink)
          .lineLimit(1)
        Text(ImportLogic.sampleSubtitle(row))
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.inkSecondary)
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      ImportSampleAmount(row: row)
    }
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
  }

  private var rowDivider: some View {
    Rectangle()
      .fill(NomiColor.separator)
      .frame(height: 1)
      .accessibilityHidden(true)
  }

  // MARK: - Derived state

  private var selectedAccountName: String? {
    guard let selectedAccountID else { return nil }
    return accounts.first { $0.id == selectedAccountID }?.displayName
  }

  /// The account row's value: the display name and last four, or "Unassigned".
  private var selectedAccountLabel: String {
    guard let selectedAccountID, let account = accounts.first(where: { $0.id == selectedAccountID }) else {
      return String(localized: "Unassigned", bundle: .module)
    }
    return account.lastFour.isEmpty ? account.displayName : "\(account.displayName) ••\(account.lastFour)"
  }

  /// The rows the dry run could not read, for "Show them". Empty unless a count is shown.
  private var unreadableRows: [[String]] {
    if case .ready(_, let dry, _)? = check?.state {
      return dry.unreadable
    }
    return []
  }

  // MARK: - Work

  /// A file was chosen: start the check. The model inspects it, then counts it or asks for columns.
  private func startCheck(_ url: URL) {
    let model = ImportCheckModel(service: fileImportService, url: url)
    check = model
    Task { await model.load() }
  }

  /// The sheet's Save writes through the model, which counts the file under the new
  /// mapping and saves nothing. Cancel never reaches the setter.
  private func mappingBinding(_ model: ImportCheckModel, current: ColumnMapping) -> Binding<ColumnMapping> {
    Binding(
      get: { model.mapping ?? current },
      set: { newMapping in
        Task { await model.applyMapping(newMapping) }
      }
    )
  }
}

/// A sample row's amount, signed: "+" and navy for a credit, "−" for a debit. The
/// decimals dim the way `NomiAmountText` dims them. VoiceOver reads the direction word.
private struct ImportSampleAmount: View {
  let row: ImportDryRunRow

  var body: some View {
    let isCredit = row.direction == .credit
    let parts = NomiAmountFormat.parts(minor: isCredit ? row.amountMinor : -row.amountMinor, showPlus: true)
    let color = isCredit ? NomiColor.navy : NomiColor.ink
    let decimals = color.opacity(NomiAmountText.decimalsOpacity(for: .amountStrong))
    let word = isCredit ? String(localized: "credit", bundle: .module) : String(localized: "debit", bundle: .module)
    (Text(parts.sign + parts.integer).foregroundStyle(color)
      + Text(parts.decimals).foregroundStyle(decimals))
      .font(NomiTextStyle.amountStrong.font)
      .lineLimit(1)
      .minimumScaleFactor(0.5)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("\(word) \(NomiFormatters.amountString(minor: row.amountMinor))")
  }
}

/// "Show them": the rows the dry run could not read, as their raw cells, so the user can see
/// exactly what Nomi will skip.
private struct UnreadableRowsSheet: View {
  let rows: [[String]]
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: NomiSpacing.xs) {
          Text(String(localized: "These rows are skipped. Nothing from them is imported.", bundle: .module))
            .nomiTextStyle(.caption)
            .foregroundStyle(NomiColor.inkSecondary)
            .padding(.horizontal, NomiSpacing.xxs)
          VStack(alignment: .leading, spacing: 0) {
            ForEach(rows.indices, id: \.self) { index in
              if index > 0 {
                Rectangle()
                  .fill(NomiColor.separator)
                  .frame(height: 1)
                  .accessibilityHidden(true)
              }
              Text(ImportSampleRow.text(rows[index]))
                .nomiTextStyle(.caption)
                .foregroundStyle(NomiColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: NomiSpacing.minTarget, alignment: .leading)
                .padding(.horizontal, NomiSpacing.sm)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .nomiCard()
        }
        .padding(.horizontal, NomiSpacing.screenGutter)
        .padding(.vertical, NomiSpacing.sm)
      }
      .background(NomiColor.ground)
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .navigationTitle(String(localized: "Rows that could not be read", bundle: .module))
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(String(localized: "Done", bundle: .module)) { dismiss() }
        }
      }
    }
    .nomiSheet(detents: [.large])
  }
}

#Preview("Import — idle") {
  NavigationStack {
    ImportEntryView(fileImportService: FakeFileImportService())
  }
  .modelContainer(ImportPreviewSupport.makeAccountContainer())
}

#Preview("Import — loading") {
  NavigationStack {
    ImportEntryView(fileImportService: FakeFileImportService(), initialCheck: ImportPreviewSupport.check(.loading))
  }
  .modelContainer(ImportPreviewSupport.makeAccountContainer())
}

#Preview("Import — check, ready") {
  NavigationStack {
    ImportEntryView(fileImportService: FakeFileImportService(), initialCheck: ImportPreviewSupport.check(
      .ready(ImportPreviewSupport.detectedPreview, ImportPreviewSupport.readyCounts, ImportPreviewSupport.detectedMapping)
    ))
  }
  .modelContainer(ImportPreviewSupport.makeAccountContainer())
}

#Preview("Import — check, every row unreadable") {
  NavigationStack {
    ImportEntryView(fileImportService: FakeFileImportService(), initialCheck: ImportPreviewSupport.check(
      .ready(ImportPreviewSupport.unknownFormatPreview, ImportPreviewSupport.unreadableOnlyCounts, ImportPreviewSupport.detectedMapping)
    ))
  }
  .modelContainer(ImportPreviewSupport.makeAccountContainer())
}

#Preview("Import — needs columns") {
  NavigationStack {
    ImportEntryView(fileImportService: FakeFileImportService(), initialCheck: ImportPreviewSupport.check(
      .needsColumns(ImportPreviewSupport.unknownFormatPreview)
    ))
  }
  .modelContainer(ImportPreviewSupport.makeAccountContainer())
}

#Preview("Import — importing") {
  NavigationStack {
    ImportEntryView(fileImportService: FakeFileImportService(), initialCheck: ImportPreviewSupport.check(.importing))
  }
  .modelContainer(ImportPreviewSupport.makeAccountContainer())
}

#Preview("Import — could not count") {
  NavigationStack {
    ImportEntryView(fileImportService: FakeFileImportService(), initialCheck: ImportPreviewSupport.check(
      .failed(ImportLogic.countFailure)
    ))
  }
  .modelContainer(ImportPreviewSupport.makeAccountContainer())
}

#Preview("Import — done") {
  NavigationStack {
    ImportEntryView(fileImportService: FakeFileImportService(), initialCheck: ImportPreviewSupport.check(
      .done(ImportSummary(created: 24, merged: 0, skipped: 2))
    ))
  }
  .modelContainer(ImportPreviewSupport.makeAccountContainer())
}

#Preview("Import — done, Ledger wired") {
  NavigationStack {
    ImportEntryView(fileImportService: FakeFileImportService(), initialCheck: ImportPreviewSupport.check(
      .done(ImportSummary(created: 24, merged: 0, skipped: 2))
    ))
  }
  .environment(\.nomiShowLedger, NomiShowLedgerAction {})
  .modelContainer(ImportPreviewSupport.makeAccountContainer())
}
