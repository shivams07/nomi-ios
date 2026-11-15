import Foundation

/// Which automatic routes Bring in your data offers in this build.
public enum OnboardingRoutes {
  /// `true` when A1 (alert intent) and A2 (automation guide) ship. Until then the
  /// Bank SMS alerts card is built and hidden, and the pill never names SMS
  /// (redesign plan section 8).
  public static let smsAvailable = false

  /// The email card's note. The provider names come from `MailProvider`, the
  /// same list the connect step offers, so the copy cannot name a provider the
  /// app does not support. The canvas said "Gmail, Yahoo and iCloud Mail"; Yahoo
  /// has no provider here, so it is not named.
  /// The note lists every field an email-sourced transaction stores:
  /// `descriptionText` (a narration of at most 160 characters, `MailNarration`),
  /// `senderDomain`, `cardFragment` and the `externalID` reference
  /// (mailbox, UIDVALIDITY and UID). It never says the whole email is kept.
  static func emailRouteNote(providers: [MailProvider] = MailProvider.allCases) -> String {
    let names = providerList(providers)
    return String(
      localized: """
        Works with \(names). Nomi reads only bank alert emails. For each one it keeps the amount, date, a short description, the sender's domain, the card's last 4 digits and a reference to the email, never the whole email.
        """,
      bundle: .module)
  }

  /// The name the user sees for a provider. The generic case is worded the way
  /// a user would say it, not as the enum's display name.
  static func providerName(_ provider: MailProvider) -> String {
    switch provider {
    case .generic: return "other IMAP mail"
    case .gmail, .icloud, .zoho: return provider.displayName
    }
  }

  /// Joins provider names as an English list: "A, B and C".
  static func providerList(_ providers: [MailProvider] = MailProvider.allCases) -> String {
    let names = providers.map(providerName)
    guard let last = names.last else { return "" }
    guard names.count > 1 else { return last }
    return names.dropLast().joined(separator: ", ") + " and " + last
  }

  /// The pill's title when the email route is on. It is also the title the
  /// disabled pill shows when no automatic route is on.
  static var emailTitle: String {
    String(localized: "Continue with email", bundle: .module)
  }

  /// The title of the Bring in your data pill, or nil when the pill must be
  /// disabled.
  ///
  /// Both routes on, with SMS available, reads "Continue with SMS and email".
  /// Email on reads "Continue with email". SMS alone, and no route at all, have
  /// no title: the SMS route has no screen in this build, so SMS alone has
  /// nowhere to go.
  static func continueTitle(
    smsOn: Bool,
    emailOn: Bool,
    smsAvailable: Bool = OnboardingRoutes.smsAvailable
  ) -> String? {
    let sms = smsOn && smsAvailable
    if sms && emailOn {
      return String(localized: "Continue with SMS and email", bundle: .module)
    }
    if emailOn {
      return emailTitle
    }
    return nil
  }
}
