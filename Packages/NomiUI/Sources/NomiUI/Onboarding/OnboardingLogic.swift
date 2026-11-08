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
///
/// B6 (form half — U1a-park hardens the IMAP transport itself): a pasted
/// Google app password or a copy-pasted address routinely carries a
/// trailing newline no typed field ever would, and IMAP's quoted-string
/// wire format (RFC 3501) cannot carry a line break inside a command at
/// all. This gate trims one and rejects the other, so a malformed value
/// never reaches `IMAPCredentials`.
enum ConnectFormGate {
  /// Whitespace *and* newlines trimmed from both ends — plain `.whitespaces`
  /// would leave a trailing `\n` from a pasted app password in place.
  static func normalized(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func isValid(provider: MailProvider, address: String, host: String, password: String) -> Bool {
    let trimmedAddress = normalized(address)
    let trimmedPassword = normalized(password)
    guard !hasEmbeddedNewline(trimmedAddress), !hasEmbeddedNewline(trimmedPassword) else { return false }

    let hasAddress = !trimmedAddress.isEmpty
    let hasPassword = !trimmedPassword.isEmpty
    let hasHost = provider.fixedHost != nil || !normalized(host).isEmpty
    return hasAddress && hasPassword && hasHost
  }

  /// A newline surviving `normalized` is embedded, not leading/trailing —
  /// more than one line inside the field itself.
  private static func hasEmbeddedNewline(_ text: String) -> Bool {
    text.contains { $0.isNewline }
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
    var lines = [
      "\(summary.scanned) emails scanned",
      "\(summary.created) transactions found",
    ]
    lines.append(contentsOf: detailLines(for: summary))
    return lines
  }

  /// The lines under the Backfill count on the Done frame. The count line
  /// already says how many were scanned and found, so only the match
  /// breakdown and the unmatched senders are added here. Those two are the only
  /// place the scan reports them, so they stay on the screen.
  static func detailLines(for summary: SyncSummary) -> [String] {
    var lines = [
      "\(summary.packMatched) matched a known bank format, \(summary.heuristicMatched) matched generically",
    ]
    if !summary.unmatchedSenders.isEmpty {
      let named = summary.unmatchedSenders.map { "\($0.domain) (\($0.count))" }.joined(separator: ", ")
      lines.append("Not matched: \(named)")
    }
    return lines
  }
}

/// The Backfill screen's controls for each phase (DEC-09, A-09 item 3). Every
/// state shows at most one white primary, or the glass Cancel while a scan
/// runs, never both. `showsLeave` is the plain white "Done" text that leaves
/// the screen while the scan carries on; it is not a button in the capsule
/// style and is absent once the scan has finished, because the white Done is
/// then the exit.
struct BackfillControls: Equatable {
  let primary: BackfillControl?
  let secondary: BackfillControl?
  let showsLeave: Bool

  static func forPhase(_ phase: BackfillPhase) -> BackfillControls {
    switch phase {
    case .notStarted, .running:
      return BackfillControls(primary: nil, secondary: .cancel, showsLeave: true)
    case .cancelled:
      return BackfillControls(primary: .resume, secondary: nil, showsLeave: true)
    case .completed:
      return BackfillControls(primary: .done, secondary: nil, showsLeave: false)
    case .failed:
      return BackfillControls(primary: .retry, secondary: nil, showsLeave: true)
    }
  }
}

enum BackfillControl: Equatable {
  case cancel, resume, done, retry

  var title: String {
    switch self {
    case .cancel: return "Cancel"
    case .resume: return "Resume"
    case .done: return "Done"
    case .retry: return "Retry"
    }
  }

  /// Cancel is the only secondary. Cancelling a scan only pauses it, so it is
  /// dark glass, never a red destructive control (DEC-09).
  var kind: NomiHeroButtonStyle.Kind {
    switch self {
    case .cancel: return .secondary
    case .resume, .done, .retry: return .primary
    }
  }
}

/// The attention card on Connect mail (ConnectMailAttention artboard). Keyed
/// on the state stream plus what this screen has already seen: the stream
/// carries `lastSync` only while connected, so the "Last synced" sentence needs
/// a connection observed in this screen's lifetime.
struct MailAttentionCopy: Equatable {
  let title: String
  let message: String
}

enum MailAttentionLogic {
  static func copy(
    for state: MailConnectionState,
    hadConnection: Bool,
    lastSync: Date?,
    now: Date
  ) -> MailAttentionCopy? {
    switch state {
    case .connected, .connecting:
      return nil
    case .disconnected:
      guard hadConnection else { return nil }
      let next = "Connect again to keep your numbers current."
      guard let lastSync else {
        return MailAttentionCopy(title: "Mail disconnected", message: next)
      }
      return MailAttentionCopy(
        title: "Mail disconnected",
        message: "Last synced \(lastSyncedPhrase(lastSync, now: now)). \(next)"
      )
    case .failed(let error):
      return MailAttentionCopy(
        title: "Couldn’t reach your mail",
        message: SyncStatusRow.failureMessage(for: error)
      )
    }
  }

  /// What follows "Last synced". A `lastSync` less than a second before `now`
  /// has no age to report, and one after `now` (clock skew, or a sync stamped
  /// this instant) has a negative one: the formatter would say "in 0 sec." or
  /// "in 1 hr.". Both read "just now". Anything older keeps the relative form.
  static func lastSyncedPhrase(_ lastSync: Date, now: Date) -> String {
    guard now.timeIntervalSince(lastSync) >= 1 else { return "just now" }
    return NomiFormatters.relativeTime.localizedString(for: lastSync, relativeTo: now)
  }
}

/// What the Connect mail screen knows about earlier connections before its
/// state stream has said anything. It is read once from `history` (persisted by
/// MH, so it survives a relaunch) and then kept up to date by the stream. The
/// two values are what `MailAttentionLogic.copy` takes as `hadConnection` and
/// `lastSync`.
struct MailAttentionSeed: Equatable {
  let hadConnection: Bool
  let lastSync: Date?

  init(history: MailConnectionHistory) {
    hadConnection = history.hasEverConnected
    lastSync = history.lastSync
  }
}

/// Copy that makes a claim about the mail credential (Amendment 4, R2). Each
/// clause is checked against the code, so a change here must be re-checked:
/// the item is saved with `kSecAttrSynchronizable: false`, so it does not sync
/// (NomiIngest, KeychainCredentialStore.swift:106). It is saved after first
/// unlock and is not ThisDeviceOnly (line 59), so an encrypted device backup
/// restored to a replacement device can carry it. That is why the sentence
/// says only "kept in" and "may need to". The only network code is the IMAP
/// fetcher (no HTTP client in any Sources file; gate G8 counts zero), and
/// transactions reach another device only through CloudKit (NomiModelContainer
/// makeCloudKit, used when the user is signed in to iCloud).
enum ConnectMailCopy {
  static let credentialCaption =
    "Your mail password is kept in this device’s Keychain. It does not sync, so you may need to enter it again on another device. Your transactions sync only if you use iCloud."
}

/// Chrome for the Backfill moment (Amendment 4, R3). The status bar is hidden
/// for all five phases, so the layout does not move when the state changes. The
/// modifier that applies this is in BackfillScreen, iOS only.
enum BackfillChrome {
  static let hidesStatusBar = true
}
