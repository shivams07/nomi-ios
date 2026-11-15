import SwiftUI

// clt-harness: include

/// The load-failed card (F3, I-4; F2a from the States board). A card with a
/// 40 pt `errorTint` circle holding an `error` circle-with-! symbol, the title
/// "Couldn’t load" (`headline`), the message (`caption`, `inkSecondary`), and
/// a full-width secondary "Try again" (44 pt, `card` fill, `separator`
/// stroke, `ink` label). The default message says the data is safe.
public struct NomiLoadFailedCard: View {
  public let message: String
  public let onRetry: () -> Void

  public init(
    message: String = "Nothing is lost. Your transactions are still on this iPhone.",
    onRetry: @escaping () -> Void
  ) {
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

      Button(action: onRetry) {
        Text("Try again", bundle: .module)
      }
      .buttonStyle(NomiSecondaryPillButtonStyle())
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .nomiCard(padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
  }
}

/// The full-width secondary pill: `card` fill, a 1 pt `separator` stroke, a
/// 44 pt height and an `ink` SemiBold 14 label.
private struct NomiSecondaryPillButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    NomiSecondaryPillBody(configuration: configuration)
  }
}

private struct NomiSecondaryPillBody: View {
  let configuration: ButtonStyleConfiguration

  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    configuration.label
      .font(.custom(NomiFont.interSemiBold, size: 14, relativeTo: .subheadline))
      .foregroundStyle(NomiColor.ink)
      .frame(maxWidth: .infinity, minHeight: NomiSpacing.minTarget)
      .background(Capsule().fill(NomiColor.card))
      .overlay(Capsule().strokeBorder(NomiColor.separator, lineWidth: 1))
      .contentShape(Capsule())
      .opacity(isEnabled ? 1 : 0.4)
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
