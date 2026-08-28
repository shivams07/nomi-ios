import NomiCore
import NomiPreview
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// State machine for the CSV/XLSX import flow: pick a file, inspect it,
/// review/adjust the detected column mapping, commit. Reached from Settings'
/// "Import from file" row.
enum ImportFlowState {
  case idle
  case inspecting
  case preview(url: URL, preview: ImportPreview, mapping: ColumnMapping)
  case noRows
  case failed(ImportError)
  case importing(url: URL, mapping: ColumnMapping)
  case done(ImportSummary)
}

/// The file picker, `ImportPreview` screen, and column-mapping UI (U7).
/// Reads `Design/**`. Must not edit it.
public struct ImportEntryView: View {
  public let fileImportService: FileImportService

  @Query(sort: \NomiCore.Account.displayName) private var accounts: [NomiCore.Account]
  @State private var flow: ImportFlowState = .idle
  @State private var isPickerPresented = false
  @State private var isMappingPresented = false
  @State private var selectedAccountID: UUID?

  public init(fileImportService: FileImportService) {
    self.fileImportService = fileImportService
  }

  /// Preview/test-only entry point — seeds `flow` directly so canvases can
  /// render the preview/no-rows/failed states without a real file pick.
  init(fileImportService: FileImportService, initialFlow: ImportFlowState) {
    self.fileImportService = fileImportService
    _flow = State(initialValue: initialFlow)
  }

  public var body: some View {
    content
      .scrollContentBackground(.hidden)
      .background(NomiColor.surfaceCanvas)
      .navigationTitle("Import from File")
      .fileImporter(
        isPresented: $isPickerPresented,
        allowedContentTypes: [.commaSeparatedText, UTType(filenameExtension: "xlsx") ?? .data]
      ) { result in
        switch result {
        case .success(let url):
          inspect(url)
        case .failure:
          break
        }
      }
  }

  @ViewBuilder
  private var content: some View {
    switch flow {
    case .idle:
      idleView
    case .inspecting, .importing:
      ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
    case .preview(let url, let preview, let mapping):
      previewView(url: url, preview: preview, mapping: mapping)
    case .noRows:
      noRowsView
    case .failed(let error):
      failedView(error)
    case .done(let summary):
      doneView(summary)
    }
  }

  private var idleView: some View {
    VStack(spacing: NomiSpacing.md) {
      Spacer()
      Text("Import transactions from a bank-exported CSV or Excel file.")
        .nomiTextStyle(.body)
        .foregroundStyle(NomiColor.textSecondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, NomiSpacing.lg)
      Button("Choose File") { isPickerPresented = true }
      Spacer()
    }
    .padding(NomiSpacing.screenGutter)
  }

  private func previewView(url: URL, preview: ImportPreview, mapping: ColumnMapping) -> some View {
    List {
      Section {
        if let bank = preview.detectedBankLabel {
          Text("Detected format: \(bank)")
            .nomiTextStyle(.body)
            .foregroundStyle(NomiColor.textPrimary)
        } else {
          Text("Unrecognized format — mapped generically")
            .nomiTextStyle(.body)
            .foregroundStyle(NomiColor.textPrimary)
        }
        Text(ImportPreviewSummary.rowCountText(preview))
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.textTertiary)
      }
      Section("Sample rows") {
        ForEach(preview.sampleRows.indices, id: \.self) { rowIndex in
          Text(preview.sampleRows[rowIndex].joined(separator: "  ·  "))
            .nomiTextStyle(.caption)
            .foregroundStyle(NomiColor.textSecondary)
        }
      }
      if !accounts.isEmpty {
        Section("Account") {
          Picker("Account", selection: $selectedAccountID) {
            Text("Unassigned").tag(UUID?.none)
            ForEach(accounts) { account in
              Text(account.displayName).tag(Optional(account.id))
            }
          }
        }
      }
      Section {
        Button("Adjust Mapping") { isMappingPresented = true }
        Button("Import") { commit(url: url, mapping: mapping) }
          .disabled(!ColumnMappingFormGate.isValid(mapping, headerCount: preview.headers.count))
      }
    }
    .scrollContentBackground(.hidden)
    .sheet(isPresented: $isMappingPresented) {
      ColumnMappingEditor(headers: preview.headers, mapping: Binding(
        get: { mapping },
        set: { flow = .preview(url: url, preview: preview, mapping: $0) }
      ))
    }
  }

  private var noRowsView: some View {
    VStack(spacing: NomiSpacing.md) {
      Spacer()
      Text("No transactions found")
        .nomiTextStyle(.title)
        .foregroundStyle(NomiColor.textPrimary)
      Text("This file didn't contain any rows Nomi could read as transactions.")
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.textTertiary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, NomiSpacing.lg)
      Button("Choose a Different File") { isPickerPresented = true }
      Spacer()
    }
    .padding(NomiSpacing.screenGutter)
  }

  private func failedView(_ error: ImportError) -> some View {
    VStack(spacing: NomiSpacing.md) {
      Spacer()
      Text(ImportErrorMessage.text(for: error))
        .nomiTextStyle(.body)
        .foregroundStyle(NomiColor.textPrimary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, NomiSpacing.lg)
      Button("Try Again") { flow = .idle }
      Spacer()
    }
    .padding(NomiSpacing.screenGutter)
  }

  private func doneView(_ summary: ImportSummary) -> some View {
    VStack(spacing: NomiSpacing.xs) {
      Spacer()
      Text("Import complete")
        .nomiTextStyle(.title)
        .foregroundStyle(NomiColor.textPrimary)
      Text("\(summary.created) added, \(summary.merged) merged, \(summary.skipped) skipped")
        .nomiTextStyle(.body)
        .foregroundStyle(NomiColor.textSecondary)
      Spacer()
    }
    .padding(NomiSpacing.screenGutter)
  }

  private func inspect(_ url: URL) {
    flow = .inspecting
    let accessed = url.startAccessingSecurityScopedResource()
    Task {
      defer { if accessed { url.stopAccessingSecurityScopedResource() } }
      do {
        let preview = try await fileImportService.inspect(url)
        if ImportPreviewSummary.isEmpty(preview) {
          flow = .noRows
        } else {
          let mapping = preview.suggestedMapping ?? ColumnMapping(
            dateColumn: 0, descriptionColumn: min(1, preview.headers.count - 1), amountColumn: min(2, preview.headers.count - 1),
            referenceColumn: nil, directionStrategy: .signedAmount, dateFormat: "dd/MM/yyyy"
          )
          flow = .preview(url: url, preview: preview, mapping: mapping)
        }
      } catch let importError as ImportError {
        flow = .failed(importError)
      } catch {
        flow = .failed(.malformedStructure(reason: error.localizedDescription))
      }
    }
  }

  private func commit(url: URL, mapping: ColumnMapping) {
    flow = .importing(url: url, mapping: mapping)
    let accessed = url.startAccessingSecurityScopedResource()
    Task {
      defer { if accessed { url.stopAccessingSecurityScopedResource() } }
      do {
        try fileImportService.saveMapping(mapping, signature: url.lastPathComponent, bankLabel: url.deletingPathExtension().lastPathComponent)
        let summary = try await fileImportService.commit(url, mapping: mapping, accountID: selectedAccountID)
        flow = .done(summary)
      } catch let importError as ImportError {
        flow = .failed(importError)
      } catch {
        flow = .failed(.malformedStructure(reason: error.localizedDescription))
      }
    }
  }
}

#Preview("Import — idle, dark") {
  NavigationStack {
    ImportEntryView(fileImportService: FakeFileImportService())
  }
  .modelContainer(ImportPreviewSupport.makeAccountContainer())
  .preferredColorScheme(.dark)
}

#Preview("Import — auto-detected, dark") {
  NavigationStack {
    ImportEntryView(fileImportService: FakeFileImportService(), initialFlow: .preview(
      url: URL(fileURLWithPath: "/tmp/statement.csv"),
      preview: ImportPreviewSupport.detectedPreview,
      mapping: ImportPreviewSupport.detectedPreview.suggestedMapping!
    ))
  }
  .modelContainer(ImportPreviewSupport.makeAccountContainer())
  .preferredColorScheme(.dark)
}

#Preview("Import — unknown format, dark") {
  NavigationStack {
    ImportEntryView(fileImportService: FakeFileImportService(), initialFlow: .preview(
      url: URL(fileURLWithPath: "/tmp/statement.csv"),
      preview: ImportPreviewSupport.unknownFormatPreview,
      mapping: ColumnMapping(dateColumn: 0, descriptionColumn: 1, amountColumn: 2, referenceColumn: nil, directionStrategy: .signedAmount, dateFormat: "dd/MM/yyyy")
    ))
  }
  .modelContainer(ImportPreviewSupport.makeAccountContainer())
  .preferredColorScheme(.dark)
}

#Preview("Import — zero rows, dark") {
  NavigationStack {
    ImportEntryView(fileImportService: FakeFileImportService(), initialFlow: .noRows)
  }
  .modelContainer(ImportPreviewSupport.makeAccountContainer())
  .preferredColorScheme(.dark)
}

#Preview("Import — malformed, dark") {
  NavigationStack {
    ImportEntryView(fileImportService: FakeFileImportService(), initialFlow: .failed(.malformedStructure(reason: "column count changes after row 12")))
  }
  .modelContainer(ImportPreviewSupport.makeAccountContainer())
  .preferredColorScheme(.dark)
}
