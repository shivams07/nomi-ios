import NomiCore
import NomiPreview
import SwiftData
import SwiftUI

/// The file the user picked, its preview, and the mapping a commit would use.
/// Carried by every state that can still act on the file, so "Adjust mapping"
/// and "Try again" have a preview to return to.
struct ImportReview {
  let url: URL
  let preview: ImportPreview
  let mapping: ColumnMapping
}

/// State machine for the CSV/XLSX import flow: pick a file, inspect it,
/// review/adjust the detected column mapping, commit. Reached from Settings'
/// "Import from file" row. One case per state the approved artboards draw
/// (`ImportIdle`, `Import`, `ImportDone`, `ImportFailed`) plus the
/// inspecting, importing and no-rows states of SIMP §3 item 20.
enum ImportFlowState {
  case idle
  case inspecting
  case preview(ImportReview)
  case noRows(ImportReview)
  case failed(ImportError, ImportReview?)
  case importing(ImportReview)
  case done(ImportSummary)
}

/// The file picker, preview, column-mapping sheet and result screens (U7; IM).
/// H0 "Import from file" in the native large-title bar. The one primary action
/// on each screen is pinned to the bottom edge. Light only.
public struct ImportEntryView: View {
  public let fileImportService: FileImportService

  @Query(sort: \NomiCore.Account.displayName) private var accounts: [NomiCore.Account]
  @Environment(\.dismiss) private var dismiss
  /// The "show the Ledger" action (FU-1). `nil` until RootView sets it, and the
  /// Done state's "View in Ledger" is hidden while it is nil.
  @Environment(\.nomiShowLedger) private var showLedger
  @State private var flow: ImportFlowState = .idle
  @State private var isPickerPresented = false
  @State private var isMappingPresented = false
  @State private var selectedAccountID: UUID?

  public init(fileImportService: FileImportService) {
    self.fileImportService = fileImportService
  }

  /// Preview/test-only entry point. Seeds `flow` directly so canvases can
  /// render every state without a real file pick.
  init(fileImportService: FileImportService, initialFlow: ImportFlowState) {
    self.fileImportService = fileImportService
    _flow = State(initialValue: initialFlow)
  }

  public var body: some View {
    content
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(NomiColor.ground)
      .navigationTitle("Import from file")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.large)
      #endif
      .fileImporter(
        isPresented: $isPickerPresented,
        allowedContentTypes: ImportFileTypes.allowed
      ) { result in
        switch result {
        case .success(let url):
          inspect(url)
        case .failure:
          break
        }
      }
      .sheet(isPresented: $isMappingPresented) {
        if let review = currentReview {
          ColumnMappingEditor(headers: review.preview.headers, mapping: mappingBinding(review))
        }
      }
  }

  @ViewBuilder
  private var content: some View {
    switch flow {
    case .idle:
      idleView
    case .inspecting:
      inspectingView
    case .preview(let review):
      previewView(review, isBusy: false)
    case .importing(let review):
      previewView(review, isBusy: true)
    case .noRows:
      noRowsView
    case .failed(let error, let review):
      failedView(error, review: review)
    case .done(let summary):
      doneView(summary)
    }
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
      pinnedPrimary("Choose file") { isPickerPresented = true }
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

  /// The preview (`Import` artboard). While importing it stays on screen with
  /// the primary disabled and busy, and Adjust mapping is disabled.
  private func previewView(_ review: ImportReview, isBusy: Bool) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        detectedCard(review.preview)
        sectionLabel("Sample rows")
        sampleRowsCard(review.preview)
        if !accounts.isEmpty {
          sectionLabel("Account")
          accountCard
        }
        adjustMappingCard
          .disabled(isBusy)
          .padding(.top, NomiSpacing.md)
      }
      .padding(.horizontal, NomiSpacing.screenGutter)
      .padding(.top, NomiSpacing.sm)
      .padding(.bottom, NomiSpacing.sm)
    }
    .safeAreaInset(edge: .bottom) {
      pinnedPrimary(
        "Import",
        isEnabled: !isBusy && ColumnMappingFormGate.isValid(review.mapping, headerCount: review.preview.headers.count),
        isBusy: isBusy
      ) {
        commit(review)
      }
    }
  }

  /// Zero parseable rows. Adjust mapping is the way out; after Save the file
  /// goes back to the preview, where Import can be tried again.
  private var noRowsView: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        NomiEmptyState(
          systemImage: "doc.text.magnifyingglass",
          title: "No transactions found",
          message: "This file didn’t contain any rows Nomi could read as transactions."
        )
        adjustMappingCard
          .padding(.top, NomiSpacing.lg)
      }
      .padding(.horizontal, NomiSpacing.screenGutter)
      .padding(.top, 96)
      .padding(.bottom, NomiSpacing.sm)
    }
    .safeAreaInset(edge: .bottom) {
      pinnedPrimary("Choose a different file") { isPickerPresented = true }
    }
  }

  /// `ImportFailed` artboard. Adjust mapping appears only when a preview exists,
  /// that is when the commit itself failed. A file that failed to inspect has
  /// no columns to adjust, so only Try again is offered.
  private func failedView(_ error: ImportError, review: ImportReview?) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: NomiSpacing.md) {
        errorCard(error)
        if review != nil {
          adjustMappingCard
        }
      }
      .padding(.horizontal, NomiSpacing.screenGutter)
      .padding(.top, NomiSpacing.sm)
      .padding(.bottom, NomiSpacing.sm)
    }
    .safeAreaInset(edge: .bottom) {
      pinnedPrimary("Try again") { tryAgain(review) }
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
            Text(ImportDoneCopy.title(summary))
              .nomiTextStyle(.headline)
              .foregroundStyle(NomiColor.ink)
            if let detail = ImportDoneCopy.detail(summary, accountName: selectedAccountName) {
              Text(detail)
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
  /// bottom edge. While busy it carries a spinner and stays disabled.
  private func pinnedPrimary(
    _ title: String,
    isEnabled: Bool = true,
    isBusy: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: NomiSpacing.xs) {
        if isBusy {
          ProgressView()
            .tint(NomiColor.onPrimary)
        }
        Text(title)
      }
    }
    .buttonStyle(NomiPrimaryButtonStyle(height: 52))
    .disabled(!isEnabled)
    .padding(.horizontal, NomiSpacing.screenGutter)
    .padding(.top, NomiSpacing.xs)
    .padding(.bottom, NomiSpacing.xs)
    .frame(maxWidth: .infinity)
    .background(NomiColor.ground)
  }

  private func sectionLabel(_ title: String) -> some View {
    Text(title)
      .nomiTextStyle(.label)
      .foregroundStyle(NomiColor.inkDeep)
      .accessibilityAddTraits(.isHeader)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, NomiSpacing.md)
      .padding(.bottom, NomiSpacing.xs)
      .padding(.horizontal, NomiSpacing.xxs)
  }

  private func detectedCard(_ preview: ImportPreview) -> some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
      Text(detectedTitle(preview))
        .nomiTextStyle(.rowBody)
        .foregroundStyle(NomiColor.ink)
      Text(ImportPreviewSummary.rowCountText(preview))
        .nomiTextStyle(.footnote)
        .foregroundStyle(NomiColor.inkSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .nomiCard(padding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
  }

  private func detectedTitle(_ preview: ImportPreview) -> String {
    if let bank = preview.detectedBankLabel {
      return "Detected format: \(bank)"
    }
    return "Unrecognized format — mapped generically"
  }

  private func sampleRowsCard(_ preview: ImportPreview) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(preview.sampleRows.indices, id: \.self) { rowIndex in
        if rowIndex > 0 {
          rowDivider
        }
        Text(preview.sampleRows[rowIndex].joined(separator: "  ·  "))
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.inkSecondary)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, minHeight: NomiSpacing.minTarget, alignment: .leading)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .nomiCard()
  }

  private var accountCard: some View {
    HStack(spacing: NomiSpacing.xs) {
      Text("Account")
        .nomiTextStyle(.rowBody)
        .foregroundStyle(NomiColor.ink)
      Spacer(minLength: NomiSpacing.xs)
      Picker("Account", selection: $selectedAccountID) {
        Text("Unassigned").tag(UUID?.none)
        ForEach(accounts) { account in
          Text(account.displayName).tag(Optional(account.id))
        }
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .tint(NomiColor.inkSecondary)
    }
    .frame(maxWidth: .infinity, minHeight: NomiSpacing.rowMinHeight)
    .nomiCard()
  }

  /// A navy text row with a trailing chevron, on a card. Opens the mapping sheet
  /// for whichever file is under review.
  private var adjustMappingCard: some View {
    Button {
      isMappingPresented = true
    } label: {
      HStack(spacing: NomiSpacing.xs) {
        Text("Adjust mapping")
          .nomiTextStyle(.rowTitle)
          .foregroundStyle(NomiColor.navy)
        Spacer(minLength: NomiSpacing.xs)
        Image(systemName: "chevron.right")
          .resizable()
          .scaledToFit()
          .frame(width: 14, height: 14)
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

  private func errorCard(_ error: ImportError) -> some View {
    HStack(alignment: .center, spacing: 12) {
      Image(systemName: "exclamationmark.circle")
        .resizable()
        .scaledToFit()
        .frame(width: 20, height: 20)
        .foregroundStyle(NomiColor.error)
        .frame(width: 40, height: 40)
        .background(Circle().fill(NomiColor.errorTint))
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
        Text("Couldn’t import this file")
          .nomiTextStyle(.headline)
          .foregroundStyle(NomiColor.ink)
        Text(ImportErrorMessage.text(for: error))
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.inkSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .nomiCard(padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
    .accessibilityElement(children: .combine)
  }

  private var rowDivider: some View {
    Rectangle()
      .fill(NomiColor.separator)
      .frame(height: 1)
      .accessibilityHidden(true)
  }

  // MARK: - Derived state

  /// The review carried by the current state, if any. The mapping sheet edits this.
  private var currentReview: ImportReview? {
    switch flow {
    case .preview(let review), .noRows(let review), .importing(let review):
      return review
    case .failed(_, let review):
      return review
    case .idle, .inspecting, .done:
      return nil
    }
  }

  private var selectedAccountName: String? {
    guard let selectedAccountID else { return nil }
    return accounts.first { $0.id == selectedAccountID }?.displayName
  }

  /// Saving the sheet always lands on the preview with the new mapping, so the
  /// user sees what Import will do before it runs. Cancel never reaches here.
  private func mappingBinding(_ review: ImportReview) -> Binding<ColumnMapping> {
    Binding(
      get: { review.mapping },
      set: { flow = .preview(ImportReview(url: review.url, preview: review.preview, mapping: $0)) }
    )
  }

  private func tryAgain(_ review: ImportReview?) {
    if let review {
      flow = .preview(review)
    } else {
      flow = .idle
    }
  }

  private func fallbackMapping(for preview: ImportPreview) -> ColumnMapping {
    ColumnMapping(
      dateColumn: 0,
      descriptionColumn: min(1, preview.headers.count - 1),
      amountColumn: min(2, preview.headers.count - 1),
      referenceColumn: nil,
      directionStrategy: .signedAmount,
      dateFormat: "dd/MM/yyyy"
    )
  }

  // MARK: - Work

  private func inspect(_ url: URL) {
    flow = .inspecting
    let accessed = url.startAccessingSecurityScopedResource()
    Task {
      defer { if accessed { url.stopAccessingSecurityScopedResource() } }
      do {
        let preview = try await fileImportService.inspect(url)
        let mapping = preview.suggestedMapping ?? fallbackMapping(for: preview)
        let review = ImportReview(url: url, preview: preview, mapping: mapping)
        if ImportPreviewSummary.isEmpty(preview) {
          flow = .noRows(review)
        } else {
          flow = .preview(review)
        }
      } catch let importError as ImportError {
        flow = .failed(importError, nil)
      } catch {
        flow = .failed(.malformedStructure(reason: error.localizedDescription), nil)
      }
    }
  }

  /// A failed commit keeps its review, so Adjust mapping and Try again can
  /// return to the preview.
  private func commit(_ review: ImportReview) {
    flow = .importing(review)
    let key = SavedMappingKey.make(from: review.preview)
    let accessed = review.url.startAccessingSecurityScopedResource()
    Task {
      defer { if accessed { review.url.stopAccessingSecurityScopedResource() } }
      do {
        try fileImportService.saveMapping(review.mapping, signature: key.signature, bankLabel: key.bankLabel)
        let summary = try await fileImportService.commit(review.url, mapping: review.mapping, accountID: selectedAccountID)
        flow = .done(summary)
      } catch let importError as ImportError {
        flow = .failed(importError, review)
      } catch {
        flow = .failed(.malformedStructure(reason: error.localizedDescription), review)
      }
    }
  }
}

#Preview("Import — idle") {
  NavigationStack {
    ImportEntryView(fileImportService: FakeFileImportService())
  }
  .modelContainer(ImportPreviewSupport.makeAccountContainer())
}

#Preview("Import — inspecting") {
  NavigationStack {
    ImportEntryView(fileImportService: FakeFileImportService(), initialFlow: .inspecting)
  }
  .modelContainer(ImportPreviewSupport.makeAccountContainer())
}

#Preview("Import — auto-detected") {
  NavigationStack {
    ImportEntryView(fileImportService: FakeFileImportService(), initialFlow: .preview(
      ImportPreviewSupport.detectedReview
    ))
  }
  .modelContainer(ImportPreviewSupport.makeAccountContainer())
}

#Preview("Import — importing") {
  NavigationStack {
    ImportEntryView(fileImportService: FakeFileImportService(), initialFlow: .importing(
      ImportPreviewSupport.detectedReview
    ))
  }
  .modelContainer(ImportPreviewSupport.makeAccountContainer())
}

#Preview("Import — unknown format") {
  NavigationStack {
    ImportEntryView(fileImportService: FakeFileImportService(), initialFlow: .preview(
      ImportPreviewSupport.unknownFormatReview
    ))
  }
  .modelContainer(ImportPreviewSupport.makeAccountContainer())
}

#Preview("Import — no rows") {
  NavigationStack {
    ImportEntryView(fileImportService: FakeFileImportService(), initialFlow: .noRows(
      ImportPreviewSupport.noRowsReview
    ))
  }
  .modelContainer(ImportPreviewSupport.makeAccountContainer())
}

#Preview("Import — failed after commit") {
  NavigationStack {
    ImportEntryView(fileImportService: FakeFileImportService(), initialFlow: .failed(
      .malformedStructure(reason: "column count changes after row 12"),
      ImportPreviewSupport.detectedReview
    ))
  }
  .modelContainer(ImportPreviewSupport.makeAccountContainer())
}

#Preview("Import — failed to inspect") {
  NavigationStack {
    ImportEntryView(fileImportService: FakeFileImportService(), initialFlow: .failed(.unreadableEncoding, nil))
  }
  .modelContainer(ImportPreviewSupport.makeAccountContainer())
}

#Preview("Import — done") {
  NavigationStack {
    ImportEntryView(fileImportService: FakeFileImportService(), initialFlow: .done(
      ImportSummary(created: 24, merged: 0, skipped: 2)
    ))
  }
  .modelContainer(ImportPreviewSupport.makeAccountContainer())
}

#Preview("Import — done, Ledger wired") {
  NavigationStack {
    ImportEntryView(fileImportService: FakeFileImportService(), initialFlow: .done(
      ImportSummary(created: 24, merged: 0, skipped: 2)
    ))
  }
  .environment(\.nomiShowLedger, NomiShowLedgerAction {})
  .modelContainer(ImportPreviewSupport.makeAccountContainer())
}
