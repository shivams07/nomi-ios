import SwiftUI

public extension View {
  /// The bottom-sheet presentation every Nomi sheet uses. Apply INSIDE the
  /// presented view's body so every presenter gets the same sheet.
  func nomiSheet(detents: Set<PresentationDetent> = [.medium, .large]) -> some View {
    self
      .presentationDetents(detents)
      .presentationDragIndicator(.visible)
      .presentationCornerRadius(NomiRadius.bar)          // 24, the v3 "sheets 24" rule
      .presentationBackground(NomiColor.surfaceRaised)
  }
}
