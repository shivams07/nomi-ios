import SwiftUI

/// About screen (U7, v5 addition; ST). One card: name, version, and the
/// privacy statement. The About artboard draws a large title and the card
/// alone, below it.
public struct AboutScreen: View {
  /// The privacy statement, verbatim from DEC-07 (nomi-ios-decisions.md).
  /// Every clause is checked against the code there. Do not edit this text
  /// without re-reading DEC-07: a human compares it with the App Store privacy
  /// form before submission (release check).
  public static let privacyText =
    "Nomi reads transaction emails from the mail account you connect and keeps your transactions on this device. If you use iCloud, they also sync to your private iCloud storage so your other devices can show them. Your mail password is kept in this device's Keychain and is sent only to your mail provider to sign in. It does not sync, so you may need to enter it again on another device. Nomi does not send your data to its developer."

  public init() {}

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        VStack(alignment: .leading, spacing: 0) {
          Text("Nomi")
            .nomiTextStyle(.title)
            .foregroundStyle(NomiColor.ink)
          Text("Version \(NomiUIModule.version)")
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
      .padding(.horizontal, NomiSpacing.screenGutter)
      .padding(.bottom, NomiSpacing.lg)
    }
    .background(NomiColor.ground)
    .navigationTitle("About")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.large)
    #endif
  }
}

#Preview("About, light") {
  NavigationStack {
    AboutScreen()
  }
  .preferredColorScheme(.light)
}
