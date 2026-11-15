import SwiftUI

/// Bring in your data: the `Bring in your data` artboard. The automatic routes
/// (email, and SMS once it ships) are selectable cards; the other ways in are
/// rows. "Continue" leads to the mail step. Every route ends in the app.
///
/// The SMS card is built and hidden: it shows only when
/// `OnboardingRoutes.smsAvailable` is true, which is false until A1 and A2 ship.
public struct BringDataScreen: View {
  /// "Continue with email", and the SMS-and-email pill once SMS is available.
  public let onMail: () -> Void
  /// "Import a bank statement".
  public let onImport: () -> Void
  /// "Add by hand". Leaves first run.
  public let onManual: () -> Void
  /// The back control. Returns to Welcome.
  public let onBack: () -> Void

  /// Email is selected on arrival, as the artboard draws it.
  @State private var emailOn = true
  @State private var smsOn = true

  public init(
    onMail: @escaping () -> Void,
    onImport: @escaping () -> Void,
    onManual: @escaping () -> Void,
    onBack: @escaping () -> Void
  ) {
    self.onMail = onMail
    self.onImport = onImport
    self.onManual = onManual
    self.onBack = onBack
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: NomiSpacing.sm) {
        navRow
        heading
        automaticSection
        otherSection
      }
      .padding(.horizontal, NomiSpacing.screenGutter)
      .padding(.top, NomiSpacing.xs)
      .padding(.bottom, NomiSpacing.md)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      footer
    }
    .background(NomiColor.ground.ignoresSafeArea())
    #if os(iOS)
    .toolbar(.hidden, for: .navigationBar)
    #endif
  }

  // MARK: - Layout

  private var navRow: some View {
    HStack {
      Button(action: onBack) {
        Image(systemName: "chevron.backward")
          .resizable()
          .scaledToFit()
          .frame(width: 20, height: 20)
          .foregroundStyle(NomiColor.ink)
          .frame(width: NomiSpacing.minTarget, height: NomiSpacing.minTarget)
          .background(Circle().fill(NomiColor.card))
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text("Back", bundle: .module))

      Spacer(minLength: NomiSpacing.xs)
      Text("Step 1 of 2", bundle: .module)
        .nomiTextStyle(.footnote)
        .foregroundStyle(NomiColor.inkSecondary)
    }
    .frame(height: NomiSpacing.navRowHeight)
  }

  /// 30 pt SemiBold, tracking -0.8: the artboard's heading. Not a `NomiTextStyle`
  /// role, which has no size between 24 and 34.
  private var heading: some View {
    Text("How should Nomi get your transactions?", bundle: .module)
      .font(.custom(NomiFont.interSemiBold, size: 30, relativeTo: .title))
      .tracking(-0.8)
      .foregroundStyle(NomiColor.ink)
      .frame(maxWidth: .infinity, alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var automaticSection: some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xs) {
      if OnboardingRoutes.smsAvailable {
        Text("Automatic · choose one or both", bundle: .module)
          .nomiTextStyle(.subhead)
          .foregroundStyle(NomiColor.inkSecondary)
          .padding(.leading, NomiSpacing.xxs)
        smsCard
      } else {
        Text("Automatic", bundle: .module)
          .nomiTextStyle(.subhead)
          .foregroundStyle(NomiColor.inkSecondary)
          .padding(.leading, NomiSpacing.xxs)
      }
      emailCard
    }
  }

  /// Hidden while `OnboardingRoutes.smsAvailable` is false. Built so that A2
  /// only has to flip the flag and give the pill its route.
  private var smsCard: some View {
    RouteCard(
      symbol: "message",
      title: "Bank SMS alerts",
      detail: "No password · from today onward",
      note: String(
        localized: "You add one automation in the Shortcuts app. Nomi only receives the bank messages it sends over.",
        bundle: .module),
      isOn: $smsOn
    )
  }

  private var emailCard: some View {
    RouteCard(
      symbol: "envelope",
      title: "Bank alert emails",
      detail: "Needs an app password · includes the last 6 months",
      note: OnboardingRoutes.emailRouteNote(),
      isOn: $emailOn
    )
  }

  private var otherSection: some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xs) {
      Text("Or start another way", bundle: .module)
        .nomiTextStyle(.subhead)
        .foregroundStyle(NomiColor.inkSecondary)
        .padding(.leading, NomiSpacing.xxs)
      VStack(spacing: 0) {
        anotherWayRow(
          symbol: "doc.text",
          title: "Import a bank statement",
          detail: "CSV or Excel",
          action: onImport
        )
        Rectangle()
          .fill(NomiColor.separator)
          .frame(height: 1)
        anotherWayRow(
          symbol: "plus",
          title: "Add by hand",
          detail: "Start empty and log as you go",
          action: onManual
        )
      }
      .padding(.horizontal, NomiSpacing.sm)
      .background(
        RoundedRectangle(cornerRadius: NomiRadius.card, style: NomiRadius.cardSheetStyle)
          .fill(NomiColor.card)
      )
    }
  }

  private func anotherWayRow(
    symbol: String,
    title: LocalizedStringKey,
    detail: LocalizedStringKey,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(alignment: .center, spacing: NomiSpacing.cardGap) {
        Image(systemName: symbol)
          .resizable()
          .scaledToFit()
          .padding(10)
          .frame(width: 42, height: 42)
          .foregroundStyle(NomiColor.navy)
          .background(Circle().fill(NomiColor.iconTile))
        VStack(alignment: .leading, spacing: 2) {
          Text(title, bundle: .module)
            .nomiTextStyle(.rowTitle)
            .foregroundStyle(NomiColor.ink)
          Text(detail, bundle: .module)
            .nomiTextStyle(.footnote)
            .foregroundStyle(NomiColor.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: "chevron.right")
          .resizable()
          .scaledToFit()
          .frame(width: 14, height: 14)
          .foregroundStyle(NomiColor.inkSecondary)
      }
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, minHeight: NomiSpacing.rowMinHeight + 12, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  /// The title of the pill, or nil when no automatic route is on. The pill is
  /// disabled then, and shows the email title it would have.
  private var continueTitle: String? {
    OnboardingRoutes.continueTitle(smsOn: smsOn, emailOn: emailOn)
  }

  private var footer: some View {
    VStack(spacing: NomiSpacing.xs) {
      Button {
        onMail()
      } label: {
        Text(continueTitle ?? OnboardingRoutes.emailTitle)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(NomiPrimaryButtonStyle(height: 54))
      .disabled(continueTitle == nil)

      Text("Everything stays on this iPhone. Nomi has no server and no account.", bundle: .module)
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.inkSecondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
    .padding(.horizontal, NomiSpacing.screenGutter)
    .padding(.vertical, NomiSpacing.sm)
    .frame(maxWidth: .infinity)
    .background(NomiColor.ground)
  }
}

/// A selectable route: a card with a check tile, 2 pt primary border when on,
/// 1 pt separator when off. The artboard draws only the selected state; off is
/// an empty ring on the same card.
private struct RouteCard: View {
  let symbol: String
  let title: LocalizedStringKey
  let detail: LocalizedStringKey
  /// Already localised by the caller (`String(localized:bundle:)`), so it is shown verbatim.
  let note: String
  @Binding var isOn: Bool

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: NomiRadius.card, style: NomiRadius.cardSheetStyle)
  }

  var body: some View {
    Button {
      isOn.toggle()
    } label: {
      VStack(alignment: .leading, spacing: NomiSpacing.xs) {
        HStack(alignment: .center, spacing: NomiSpacing.cardGap) {
          Image(systemName: symbol)
            .resizable()
            .scaledToFit()
            .padding(10)
            .frame(width: 42, height: 42)
            .foregroundStyle(NomiColor.navy)
            .background(Circle().fill(NomiColor.iconTile))
          VStack(alignment: .leading, spacing: 2) {
            Text(title, bundle: .module)
              .nomiTextStyle(.headline)
              .foregroundStyle(NomiColor.ink)
            Text(detail, bundle: .module)
              .nomiTextStyle(.footnote)
              .foregroundStyle(NomiColor.inkSecondary)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          checkTile
        }
        Text(verbatim: note)
          .nomiTextStyle(.footnote)
          .foregroundStyle(NomiColor.inkSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(NomiSpacing.sm)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(shape.fill(NomiColor.card))
      .overlay {
        shape.strokeBorder(isOn ? NomiColor.primary : NomiColor.separator, lineWidth: isOn ? 2 : 1)
      }
      .contentShape(shape)
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isOn ? .isSelected : .isButton)
  }

  private var checkTile: some View {
    ZStack {
      if isOn {
        Circle().fill(NomiColor.primary)
        Image(systemName: "checkmark")
          .resizable()
          .scaledToFit()
          .padding(7)
          .foregroundStyle(NomiColor.onPrimary)
      } else {
        Circle().strokeBorder(NomiColor.inkSecondary, lineWidth: 1.5)
      }
    }
    .frame(width: 28, height: 28)
    .accessibilityHidden(true)
  }
}

#Preview("Bring in your data") {
  BringDataScreen(onMail: {}, onImport: {}, onManual: {}, onBack: {})
}

#Preview("Bring in your data · AX3") {
  BringDataScreen(onMail: {}, onImport: {}, onManual: {}, onBack: {})
    .environment(\.dynamicTypeSize, .accessibility3)
}
