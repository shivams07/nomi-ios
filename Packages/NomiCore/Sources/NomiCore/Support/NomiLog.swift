import Foundation
import OSLog

/// The app's loggers, one category per area. Every swallowed store, keychain
/// or pipeline failure is reported through one of these, so a field report
/// can say which step failed without the app having to show it.
///
/// Log lines carry no user data. See `describe(_:)` and the rule under it.
public enum NomiLog {
  public static let subsystem = "com.shivams07.nomi"

  public static var sync: Logger { Logger(subsystem: subsystem, category: "sync") }
  public static var ingest: Logger { Logger(subsystem: subsystem, category: "ingest") }
  public static var store: Logger { Logger(subsystem: subsystem, category: "store") }
  public static var notifications: Logger { Logger(subsystem: subsystem, category: "notifications") }

  /// The only form an `Error` takes in a log line: `"<module.Type>#<code>"`,
  /// e.g. `"NomiIngest.IMAPTransportError#4"`. Never the description, which can
  /// carry server text, addresses or narrations.
  ///
  /// Log-line rule for every caller: interpolate only `describe(_:)`, counts,
  /// UIDs and durations, each with `privacy: .public`. Never an amount, a
  /// description or narration, a merchant, an email address, a host or a file
  /// path.
  public static func describe(_ error: Error) -> String {
    "\(String(reflecting: type(of: error)))#\((error as NSError).code)"
  }
}
