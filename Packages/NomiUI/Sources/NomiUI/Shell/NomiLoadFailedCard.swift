import SwiftUI

// clt-harness: include

/// The load-failed card (F3, I-4), drawn from the approved `LoadFailed.dc.html`
/// artboard, which governs over the plan where they differ (coordinator ruling).
/// A card with a 40 pt `errorTint` circle holding an `error` circle-with-! symbol,
/// the title "Couldn’t load" (`headline`), the message (`caption`, `inkSecondary`),
/// and the card's single primary: a 44 pt black Retry (`NomiPrimaryButtonStyle`).
public struct NomiLoadFailedCard: View {
  public let message: String
  public let onRetry: () -> Void

  public init(message: String, onRetry: @escaping () -> Void) {
    self.message = message
    self.onRetry = onRetry
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .center, spacing: 12) {
        Image(systemName: "exclamationmark.circle")
          .resizable()
          .scaledToFit()
          .frame(width: 20, height: 20)
          .foregroundStyle(NomiColor.error)
          .frame(width: 40, height: 40)
          .background(Circle().fill(NomiColor.errorTint))
          .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 2) {
          Text("Couldn’t load")
            .nomiTextStyle(.headline)
            .foregroundStyle(NomiColor.ink)
          Text(message)
            .nomiTextStyle(.caption)
            .foregroundStyle(NomiColor.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      Button("Retry", action: onRetry)
        .buttonStyle(NomiPrimaryButtonStyle(height: 44))
        .frame(maxWidth: .infinity)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .nomiCard(padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
  }
}

#Preview("Load failed · default") {
  NomiLoadFailedCard(message: "Recent transactions didn’t load.") {}
    .padding(20)
    .background(NomiColor.ground)
    .preferredColorScheme(.light)
}

#Preview("Load failed · AX3") {
  NomiLoadFailedCard(message: "Recent transactions didn’t load.") {}
    .padding(20)
    .background(NomiColor.ground)
    .environment(\.dynamicTypeSize, .accessibility3)
    .preferredColorScheme(.light)
}
