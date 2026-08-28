import Foundation
import NomiCore

/// The four providers §1.1 tests and supports at launch. Host/port are fixed
/// per provider; only "Generic IMAP" asks the user to type a host.
public enum MailProvider: String, CaseIterable, Identifiable, Sendable, Hashable {
  case gmail, icloud, zoho, generic

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .gmail: return "Gmail"
    case .icloud: return "iCloud Mail"
    case .zoho: return "Zoho Mail"
    case .generic: return "Generic IMAP"
    }
  }

  /// `nil` means the field is user-entered (Generic IMAP only).
  public var fixedHost: String? {
    switch self {
    case .gmail: return "imap.gmail.com"
    case .icloud: return "imap.mail.me.com"
    case .zoho: return "imap.zoho.in"
    case .generic: return nil
    }
  }

  public var port: Int { 993 }

  /// §1.1: what to tell the user about the password field for each provider.
  public var passwordInstructions: String {
    switch self {
    case .gmail: return "Use a Google App Password. Your Google account needs 2-Step Verification turned on first."
    case .icloud: return "Use an app-specific password generated at appleid.apple.com, not your Apple ID password."
    case .zoho: return "Use a Zoho application-specific password from your Zoho account security settings."
    case .generic: return "Enter your mailbox password."
    }
  }
}

/// The connect form's Save gate: an address is always required; a host is
/// only required when the provider does not fix one.
enum ConnectFormGate {
  static func isValid(provider: MailProvider, address: String, host: String, password: String) -> Bool {
    let hasAddress = !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let hasPassword = !password.isEmpty
    let hasHost = provider.fixedHost != nil || !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    return hasAddress && hasPassword && hasHost
  }
}

/// `MailError` copy. Named per case, per the U7 acceptance criteria — no
/// generic "something went wrong".
enum MailErrorMessage {
  static func text(for error: MailError) -> String {
    switch error {
    case .authenticationFailed:
      return "That address or password wasn't accepted. Double-check the app password and try again."
    case .connectionFailed:
      return "Couldn't reach the mail server. Check your connection and try again."
    case .unknown(let detail):
      return detail.isEmpty ? "Something went wrong connecting to mail." : detail
    }
  }
}

/// Pure fraction/completion math for the backfill hero screen — same shape as
/// `BackfillBanner`'s private fraction calc, kept separate because this unit
/// owns `Onboarding/**` and must not edit `Shell/BackfillBanner.swift`.
enum BackfillMath {
  static func fraction(_ progress: BackfillProgress) -> Double {
    guard progress.total > 0 else { return 0 }
    return min(max(Double(progress.scanned) / Double(progress.total), 0), 1)
  }

  static func isComplete(_ progress: BackfillProgress) -> Bool {
    progress.total > 0 && progress.scanned >= progress.total
  }
}

/// The backfill completion copy — the §1.5 counters (`packMatched` /
/// `heuristicMatched`) reported as plain text, not a chart or a badge.
enum BackfillCompletionSummary {
  static func lines(for summary: SyncSummary) -> [String] {
    [
      "\(summary.scanned) emails scanned",
      "\(summary.created) transactions found",
      "\(summary.packMatched) matched a known bank format, \(summary.heuristicMatched) matched generically",
    ]
  }
}
