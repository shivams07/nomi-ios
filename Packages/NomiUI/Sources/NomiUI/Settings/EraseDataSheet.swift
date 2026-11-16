import Foundation
import NomiCore
import Observation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// The copy for "Erase all Nomi data?" (S9a step 5, I-13 Amendment 1). Pure, so the
/// gate, the three scope bodies and the failure copy can be tested without rendering.
enum EraseDataCopy {
  static let title = "Erase all Nomi data?"
  static let confirmationWord = "ERASE"
  static let confirmationPrompt = "Type ERASE to confirm"
  static let keepTitle = "Keep"
  static let eraseTitle = "Erase"
  static let doneTitle = "Done"

  /// The body, by the scope the eraser reports now. Nothing here is developer text:
  /// the unavailable reason goes to "Copy details", not into the sentence.
  static func body(for scope: EraseScope) -> String {
    switch scope {
    case .everywhere:
      return
        "Every transaction, account, budget and rule is removed from this iPhone and from your iCloud. Your other devices lose them too when they next sync. The mail password is removed from this iPhone; another device keeps its own until you erase or disconnect mail there. This cannot be undone."
    case .thisDeviceOnly:
      return
        "Nomi isn’t syncing with iCloud right now, so this erases this iPhone only. If your data is in iCloud, it comes back the next time Nomi syncs. To erase it everywhere, turn iCloud on for Nomi and erase again. This cannot be undone on this iPhone."
    case .unavailable:
      return
        "Nomi couldn’t open your saved data this time, so there is nothing it can erase. Close Nomi and open it again, then try."
    }
  }

  /// The copy for a failed erase. `busy` and `incomplete` are the two the sheet
  /// explains. Anything else may still have removed some data, so it reads as
  /// incomplete, which is safe to retry.
  static func failureText(for error: Error) -> String {
    guard let eraseError = error as? EraseError else { return incompleteText }
    switch eraseError {
    case .busy:
      return "Nomi is still syncing. Nothing was erased. Try again in a moment."
    case .incomplete:
      return incompleteText
    case .unavailable:
      return body(for: .unavailable(reason: ""))
    }
  }

  private static let incompleteText = "Some data couldn’t be removed. Try again."

  /// The unavailable scope has no button: the store was never opened, so nothing can
  /// be erased from here.
  static func showsEraseButton(for scope: EraseScope) -> Bool {
    if case .unavailable = scope { return false }
    return true
  }

  /// The gate is the exact word, case-sensitive, with no trimming.
  static func isConfirmed(_ text: String) -> Bool {
    text == confirmationWord
  }
}

/// The erase sheet's state: the typed gate, one call to the eraser, and the failure
/// copy. The view reads it and never calls the eraser itself.
@Observable @MainActor final class EraseDataModel {
  @ObservationIgnored private let eraser: any DataErasing

  var confirmation = ""
  /// True from the moment an erase starts until it returns. It shuts the gate, so a
  /// second press does nothing, and the sheet cannot be dismissed meanwhile.
  private(set) var isErasing = false
  /// The copy for the last failed erase. Cleared when the next erase starts.
  private(set) var failureText: String?

  init(eraser: any DataErasing) {
    self.eraser = eraser
  }

  var scope: EraseScope { eraser.scope }

  var showsEraseButton: Bool { EraseDataCopy.showsEraseButton(for: scope) }

  /// The gate: the scope allows an erase, the word is typed exactly, and nothing is
  /// already running.
  var canErase: Bool {
    showsEraseButton && EraseDataCopy.isConfirmed(confirmation) && !isErasing
  }

  /// Runs the erase once. Returns true when the eraser returned, which is when the app
  /// goes back to Welcome. A failure keeps the sheet open with its copy and reopens the
  /// gate, so the user can retry.
  @discardableResult
  func erase() async -> Bool {
    guard canErase else { return false }
    isErasing = true
    failureText = nil
    defer { isErasing = false }
    do {
      try await eraser.eraseEverything()
      return true
    } catch {
      failureText = EraseDataCopy.failureText(for: error)
      return false
    }
  }
}

/// The "Erase all Nomi data?" sheet. The row in Settings opens it, and it draws its
/// Erase button in the error fill.
struct EraseDataSheet: View {
  @State private var model: EraseDataModel
  @Environment(\.dismiss) private var dismiss

  init(eraser: any DataErasing) {
    _model = State(initialValue: EraseDataModel(eraser: eraser))
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: NomiSpacing.sm) {
        Text(EraseDataCopy.title)
          .nomiTextStyle(.title)
          .foregroundStyle(NomiColor.ink)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityAddTraits(.isHeader)

        Text(EraseDataCopy.body(for: model.scope))
          .nomiTextStyle(.rowBody)
          .foregroundStyle(NomiColor.ink)
          .fixedSize(horizontal: false, vertical: true)

        if let details = SettingsLogic.copyableDetails(for: model.scope) {
          CopyDetailsLink(text: details)
        }

        if model.showsEraseButton {
          confirmationField
        }

        if model.isErasing {
          ProgressView()
            .frame(maxWidth: .infinity, minHeight: 54)
        } else {
          buttons
        }

        if let failure = model.failureText {
          NomiStatusNote(failure, tone: .error, systemImage: "exclamationmark.triangle")
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, NomiSpacing.screenGutter)
      .padding(.vertical, NomiSpacing.md)
    }
    .background(NomiColor.ground)
    .interactiveDismissDisabled(model.isErasing)
  }

  private var confirmationField: some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
      Text(EraseDataCopy.confirmationPrompt)
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.inkSecondary)
        .fixedSize(horizontal: false, vertical: true)
      TextField(EraseDataCopy.confirmationWord, text: $model.confirmation)
        .nomiTextStyle(.rowBody)
        .foregroundStyle(NomiColor.ink)
        .autocorrectionDisabled()
        .accessibilityLabel(EraseDataCopy.confirmationPrompt)
        .padding(.horizontal, NomiSpacing.xs)
        .frame(maxWidth: .infinity, minHeight: NomiSpacing.minTarget, alignment: .leading)
        .background {
          RoundedRectangle(cornerRadius: 12).fill(NomiColor.card)
        }
        .overlay {
          RoundedRectangle(cornerRadius: 12).strokeBorder(NomiColor.separator, lineWidth: 1)
        }
    }
  }

  @ViewBuilder
  private var buttons: some View {
    VStack(spacing: NomiSpacing.xs) {
      if model.showsEraseButton {
        Button {
          Task {
            if await model.erase() { dismiss() }
          }
        } label: {
          Text(EraseDataCopy.eraseTitle)
        }
        .buttonStyle(EraseButtonStyle())
        .disabled(!model.canErase)

        Button(EraseDataCopy.keepTitle) { dismiss() }
          .buttonStyle(NomiSecondaryButtonStyle())
      } else {
        Button(EraseDataCopy.doneTitle) { dismiss() }
          .buttonStyle(NomiSecondaryButtonStyle())
      }
    }
    .frame(maxWidth: .infinity)
  }
}

/// The destructive primary: the error fill with a light label, 54 pt, and 40% when the
/// gate is shut. The same height and shape as `NomiPrimaryButtonStyle`.
struct EraseButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    EraseButtonBody(configuration: configuration)
  }
}

private struct EraseButtonBody: View {
  let configuration: ButtonStyleConfiguration
  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    configuration.label
      .nomiTextStyle(.button)
      .foregroundStyle(NomiColor.card)
      .frame(maxWidth: .infinity, minHeight: 54)
      .background(Capsule().fill(NomiColor.error))
      .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
  }
}

/// "Copy details": writes developer text to the pasteboard, then says "Copied" for two
/// seconds. The text is shown on screen as the link's own value, not hidden.
struct CopyDetailsLink: View {
  let text: String
  @State private var copied = false

  var body: some View {
    Button {
      SettingsClipboard.copy(text)
      copied = true
      Task {
        try? await Task.sleep(for: .seconds(2))
        copied = false
      }
    } label: {
      Text(copied ? "Copied" : "Copy details")
        .nomiTextStyle(.button)
        .foregroundStyle(NomiColor.navy)
        .frame(maxWidth: .infinity, minHeight: NomiSpacing.minTarget, alignment: .leading)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

/// The one place Settings writes to the pasteboard. The package also builds for macOS,
/// so both pasteboard APIs are named here, as the transaction detail copy does.
enum SettingsClipboard {
  static func copy(_ text: String) {
    #if os(iOS)
    UIPasteboard.general.string = text
    #elseif os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    #endif
  }
}

/// An eraser that reports a fixed scope and erases nothing. Used by the previews only.
@MainActor
final class EraseDataPreviewEraser: DataErasing {
  let scope: EraseScope

  init(scope: EraseScope) {
    self.scope = scope
  }

  func eraseEverything() async throws {}
}

#Preview("Erase sheet · everywhere, light") {
  EraseDataSheet(eraser: EraseDataPreviewEraser(scope: .everywhere))
    .preferredColorScheme(.light)
}

#Preview("Erase sheet · this iPhone only, light") {
  EraseDataSheet(eraser: EraseDataPreviewEraser(scope: .thisDeviceOnly))
    .preferredColorScheme(.light)
}

#Preview("Erase sheet · unavailable, light") {
  EraseDataSheet(eraser: EraseDataPreviewEraser(scope: .unavailable(reason: "SwiftDataError: could not open the persistent store")))
    .preferredColorScheme(.light)
}
