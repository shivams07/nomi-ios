// clt-harness: include
import SwiftUI

public extension View {
  /// The bottom-sheet presentation every Nomi sheet uses. Apply INSIDE the
  /// presented view's body so every presenter gets the same sheet. Pass
  /// `selection` to bind the detent; sheets that do not need it leave it nil.
  @ViewBuilder
  func nomiSheet(
    detents: Set<PresentationDetent> = [.medium, .large],
    selection: Binding<PresentationDetent>? = nil
  ) -> some View {
    if let selection {
      self
        .presentationDetents(detents, selection: selection)
        .nomiSheetChrome()
    } else {
      self
        .presentationDetents(detents)
        .nomiSheetChrome()
    }
  }
}

private extension View {
  /// Drag indicator, 32 corner radius, the ground background and the navy tint
  /// shared by every sheet. The tint keeps sheet bar buttons (Cancel, Save) navy
  /// inside the iOS 26 glass; without it they draw ink.
  func nomiSheetChrome() -> some View {
    self
      .presentationDragIndicator(.visible)
      .presentationCornerRadius(NomiRadius.sheet)
      .presentationBackground(NomiColor.ground)
      .tint(NomiColor.navy)
  }
}
