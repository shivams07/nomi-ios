import Foundation

/// The Connect mail guide for each provider (S12b). It extends the app's existing
/// `MailProvider` (OnboardingLogic.swift): no provider is added or renamed, and
/// Yahoo is not one, because the app has no IMAP host for it.
///
/// Each step names only what the provider's help page says. A step the page does
/// not confirm stays general, and the PR body says which.
extension MailProvider {
  /// The numbered steps in the guide card. Empty for generic IMAP.
  var steps: [String] {
    switch self {
    case .gmail:
      return [
        "Turn on 2-Step Verification in your Google account",
        "Create an app password for Nomi",
        "Paste the 16-character password below",
      ]
    case .icloud:
      return [
        "Sign in at account.apple.com",
        "Under Sign-In and Security, choose App-Specific Passwords",
        "Generate an app-specific password and paste it below",
      ]
    case .zoho:
      return [
        "Sign in to your Zoho Account and open Security",
        "Choose Application Specific Passwords, then Generate New Password",
        "Enter a name, click Generate, and paste the password below",
      ]
    case .generic:
      return []
    }
  }

  /// The page the password is made on. Nil for generic IMAP.
  var appPasswordURL: URL? {
    switch self {
    case .gmail: return URL(string: "https://myaccount.google.com/apppasswords")
    case .icloud: return URL(string: "https://account.apple.com")
    case .zoho: return URL(string: "https://accounts.zoho.com")
    case .generic: return nil
    }
  }

  /// The button under the steps. Nil exactly when `appPasswordURL` is nil.
  var appPasswordLinkTitle: String? {
    switch self {
    case .gmail: return "Open Google app passwords"
    case .icloud: return "Open Apple Account"
    case .zoho: return "Open Zoho Accounts"
    case .generic: return nil
    }
  }

  /// The heading over the steps card. Nil for generic IMAP, which has no card.
  var guideTitle: String? {
    steps.isEmpty ? nil : "\(displayName) needs an app password"
  }

  /// What generic IMAP is told instead of steps. It names no provider's page.
  static let genericPasswordNote = "Use your provider’s app password or mail password."
}

/// The footnote under the Connect button. The Keychain sentence is
/// `ConnectMailCopy.credentialCaption`, unchanged and tested there; the scope
/// sentence follows it. Each sentence is checked against code in the PR body.
enum ConnectMailFootnote {
  static let text =
    ConnectMailCopy.credentialCaption
    + " Nomi reads emails from bank and payment senders and keeps only transaction alerts."
}
