import SwiftUI

/// About screen (U7, v5 addition; ST; S9b). An identity card with the name,
/// the version and the privacy statement, then a card of rows: privacy policy
/// and terms (shown only once their URLs are set), support, and licences.
/// The About artboard draws a large title and the card alone, below it.
public struct AboutScreen: View {
  /// The privacy statement, verbatim from DEC-07 (nomi-ios-decisions.md).
  /// Every clause is checked against the code there. Do not edit this text
  /// without re-reading DEC-07: a human compares it with the App Store privacy
  /// form before submission (release check).
  public static let privacyText =
    "Nomi reads transaction emails from the mail account you connect and keeps your transactions on this device. If you use iCloud, they also sync to your private iCloud storage so your other devices can show them. Your mail password is kept in this device's Keychain and is sent only to your mail provider to sign in. It does not sync, so you may need to enter it again on another device. Nomi does not send your data to its developer."

  public init() {}

  public var body: some View {
    let rows = AboutLogic.visibleRows(privacy: LegalLinks.privacyPolicy, terms: LegalLinks.terms)
    let footer = AboutLogic.footer(
      publisherName: LegalLinks.publisherName,
      year: Calendar.current.component(.year, from: Date())
    )
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        identityCard
        rowsCard(rows)
        if let footer {
          Text(footer)
            .nomiTextStyle(.footnote)
            .foregroundStyle(NomiColor.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, NomiSpacing.sm)
        }
      }
      .padding(.horizontal, NomiSpacing.screenGutter)
      .padding(.bottom, NomiSpacing.lg)
    }
    .background(NomiColor.ground)
    .navigationTitle(String(localized: "About and privacy", bundle: .module))
    #if os(iOS)
    .navigationBarTitleDisplayMode(.large)
    #endif
  }

  private var identityCard: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Nomi")
        .nomiTextStyle(.title)
        .foregroundStyle(NomiColor.ink)
      Text(AboutLogic.versionLine(bundle: .main))
        .nomiTextStyle(.footnote)
        .foregroundStyle(NomiColor.inkSecondary)
        .padding(.top, NomiSpacing.xxs)
      Rectangle()
        .fill(NomiColor.separator)
        .frame(height: 1)
        .padding(.top, 14)
        .accessibilityHidden(true)
      Text(Self.privacyText)
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.inkSecondary)
        .lineSpacing(4)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 14)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .nomiCard(padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
  }

  private func rowsCard(_ rows: [AboutLogic.Row]) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
        if index > 0 {
          Rectangle()
            .fill(NomiColor.separator)
            .frame(height: 1)
            .accessibilityHidden(true)
        }
        rowView(row)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .nomiCard()
    .padding(.top, NomiSpacing.sm)
  }

  @ViewBuilder
  private func rowView(_ row: AboutLogic.Row) -> some View {
    switch row {
    case .privacyPolicy:
      if let url = LegalLinks.privacyPolicy {
        Link(destination: url) {
          linkLabel("Privacy policy")
        }
        .buttonStyle(.plain)
      }
    case .termsOfUse:
      if let url = LegalLinks.terms {
        Link(destination: url) {
          linkLabel("Terms of use")
        }
        .buttonStyle(.plain)
      }
    case .support:
      supportRow
    case .licences:
      NavigationLink {
        LicensesScreen()
      } label: {
        navigationLabel("Open-source licences")
      }
      .buttonStyle(.plain)
    }
  }

  /// The support address as selectable text, with a mail link beside it.
  private var supportRow: some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
      Text("Support", bundle: .module)
        .nomiTextStyle(.rowBody)
        .foregroundStyle(NomiColor.ink)
      Text(LegalLinks.supportEmail)
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.inkSecondary)
        .textSelection(.enabled)
      if let mailto = AboutLogic.mailtoURL(address: LegalLinks.supportEmail) {
        Link(destination: mailto) {
          Text("Email support", bundle: .module)
            .nomiTextStyle(.rowBody)
            .foregroundStyle(NomiColor.primary)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, NomiSpacing.xs)
  }

  private func linkLabel(_ title: LocalizedStringKey) -> some View {
    HStack(spacing: NomiSpacing.xs) {
      Text(title, bundle: .module)
        .nomiTextStyle(.rowBody)
        .foregroundStyle(NomiColor.ink)
      Spacer(minLength: 0)
      AboutRowChevron(symbol: "arrow.up.right")
    }
    .frame(maxWidth: .infinity, minHeight: NomiSpacing.rowMinHeight, alignment: .leading)
    .contentShape(Rectangle())
  }

  private func navigationLabel(_ title: LocalizedStringKey) -> some View {
    HStack(spacing: NomiSpacing.xs) {
      Text(title, bundle: .module)
        .nomiTextStyle(.rowBody)
        .foregroundStyle(NomiColor.ink)
      Spacer(minLength: 0)
      AboutRowChevron(symbol: "chevron.right")
    }
    .frame(maxWidth: .infinity, minHeight: NomiSpacing.rowMinHeight, alignment: .leading)
    .contentShape(Rectangle())
  }
}

/// The trailing symbol on an About row: 16 pt, `inkSecondary`, hidden from
/// VoiceOver because the row is the control.
private struct AboutRowChevron: View {
  let symbol: String

  var body: some View {
    Image(systemName: symbol)
      .resizable()
      .scaledToFit()
      .frame(width: 16, height: 16)
      .foregroundStyle(NomiColor.inkSecondary)
      .accessibilityHidden(true)
  }
}

#Preview("About, light") {
  NavigationStack {
    AboutScreen()
  }
  .preferredColorScheme(.light)
}
