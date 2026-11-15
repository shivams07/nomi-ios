import SwiftUI

/// The first screen of first run: the `Welcome (new)` artboard. A full-bleed
/// hero moment on the Moss ramp (I-9): the wordmark, the promise, two sample
/// alerts tilted as if pinned up, and "Get started".
///
/// It has no nav bar and no skip. The next step is Bring in your data, and
/// every exit from first run is on that step or the mail step after it.
public struct WelcomeScreen: View {
  /// Leaves Welcome for Bring in your data.
  public let onStart: () -> Void

  public init(onStart: @escaping () -> Void) {
    self.onStart = onStart
  }

  public var body: some View {
    GeometryReader { outer in
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          wordmark
          heading
            .padding(.top, 18)
          bodyCopy
            .padding(.top, NomiSpacing.sm)
          samples
            .padding(.top, NomiSpacing.xl)
          Spacer(minLength: NomiSpacing.lg)
          footer
            .padding(.top, NomiSpacing.lg)
        }
        .padding(.horizontal, NomiSpacing.md)
        .padding(.top, NomiSpacing.md)
        .padding(.bottom, NomiSpacing.sm)
        .frame(maxWidth: .infinity, minHeight: outer.size.height, alignment: .topLeading)
      }
      .scrollBounceBehavior(.basedOnSize)
    }
    .background {
      // The navy top of the ramp sits under the status bar, so the bar is light.
      // Publishing the tone is the hero scaffold's rule (SB1); hiding the bar is
      // not used on a hero.
      Rectangle()
        .fill(NomiHeroGradient.moment)
        .ignoresSafeArea()
        .preference(key: NomiStatusBarToneKey.self, value: .light)
    }
    #if os(iOS)
    .toolbar(.hidden, for: .navigationBar)
    #endif
  }

  private var wordmark: some View {
    Text("Nomi", bundle: .module)
      .font(.custom(NomiFont.interSemiBold, size: 15, relativeTo: .body))
      .tracking(0.2)
      .foregroundStyle(NomiColor.heroText)
  }

  /// 44 pt SemiBold, tracking -1.6. Not a `NomiTextStyle` role: the roles stop at
  /// 34 for a large title, and this display size belongs to this screen only.
  private var heading: some View {
    Text("Your spending, logged for you.", bundle: .module)
      .font(.custom(NomiFont.interSemiBold, size: 44, relativeTo: .largeTitle))
      .tracking(-1.6)
      .foregroundStyle(NomiColor.heroText)
      .frame(maxWidth: .infinity, alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var bodyCopy: some View {
    Text("Nomi reads the bank and card alerts already in your inbox and turns them into a ledger, kept on this iPhone.", bundle: .module)
      .nomiTextStyle(.body)
      .foregroundStyle(NomiColor.heroText)
      .frame(maxWidth: 310, alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
  }

  /// Two sample alerts, decorative for VoiceOver: the body copy carries the
  /// promise, and the samples only show what the screen means.
  private var samples: some View {
    VStack(spacing: NomiSpacing.sm) {
      glassAlert
        .rotationEffect(.degrees(-2))
        .frame(maxWidth: .infinity, alignment: .leading)
      whiteRow
        .rotationEffect(.degrees(1.5))
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .accessibilityHidden(true)
  }

  /// The alert, on dark glass (`heroControl`), 300 pt wide at most.
  private var glassAlert: some View {
    HStack(alignment: .center, spacing: NomiSpacing.cardGap) {
      Image(systemName: "envelope")
        .resizable()
        .scaledToFit()
        .padding(8)
        .frame(width: 34, height: 34)
        .foregroundStyle(NomiColor.navyDeep)
        .background(Circle().fill(NomiColor.heroText))
      Text("\"Rs.845.00 debited from A/c XX4471 to OLACABS\"")
        .nomiTextStyle(.subhead)
        .foregroundStyle(NomiColor.heroText)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.vertical, 14)
    .padding(.horizontal, NomiSpacing.sm)
    .frame(maxWidth: 300, alignment: .leading)
    .nomiGlass(.heroControl, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
  }

  /// The Ola row, white (`card`), 290 pt wide at most. Its amount is the
  /// app's own amount typesetting, with the paise dimmed.
  private var whiteRow: some View {
    HStack(alignment: .center, spacing: NomiSpacing.cardGap) {
      Image(systemName: "car.fill")
        .resizable()
        .scaledToFit()
        .padding(9)
        .frame(width: 34, height: 34)
        .foregroundStyle(NomiColor.navy)
        .background(Circle().fill(NomiColor.iconTile))
      VStack(alignment: .leading, spacing: 2) {
        Text("Ola", bundle: .module)
          .nomiTextStyle(.rowTitle)
          .foregroundStyle(NomiColor.ink)
        Text("Ride-hailing · HDFC ••4471", bundle: .module)
          .nomiTextStyle(.footnote)
          .foregroundStyle(NomiColor.inkSecondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      NomiAmountText(minor: -84500, style: .amountStrong)
        .fixedSize(horizontal: true, vertical: false)
    }
    .padding(.vertical, NomiSpacing.xs + NomiSpacing.xxs)
    .padding(.horizontal, NomiSpacing.sm)
    .frame(maxWidth: 290)
    .background(
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .fill(NomiColor.card)
    )
  }

  private var footer: some View {
    VStack(spacing: NomiSpacing.sm) {
      Button {
        onStart()
      } label: {
        Text("Get started", bundle: .module)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(NomiHeroButtonStyle(.primary))
      .frame(maxWidth: .infinity)

      Text("No sign-up and no server. Your data stays on this iPhone and syncs to your private iCloud if you use iCloud.", bundle: .module)
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.heroText)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
  }
}

#Preview("Welcome") {
  WelcomeScreen(onStart: {})
}

#Preview("Welcome · AX3") {
  WelcomeScreen(onStart: {})
    .environment(\.dynamicTypeSize, .accessibility3)
}
