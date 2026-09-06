import CryptoKit
import Foundation

/// Uppercases, collapses whitespace, and strips digit runs from raw narration.
/// Derived from `descriptionText` ONLY — never from `merchantName`. Feeds both
/// dedupe and rule matching, so it must be byte-identical across every ingester.
public func normalizeDescription(_ raw: String) -> String {
  let upper = raw.uppercased()
  let digitsStripped = upper.replacingOccurrences(
    of: "[0-9]+", with: "", options: .regularExpression
  )
  let collapsed = digitsStripped.replacingOccurrences(
    of: "\\s+", with: " ", options: .regularExpression
  )
  return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// `sha256("\(startOfDay(date, NomiCalendar.india))|\(amountMinor)|\(directionRaw)|\(normalizedDescription)")`
///
/// The calendar defaults to `NomiCalendar.india` and callers should leave it
/// there: the key must not depend on where the device is. See `NomiCalendar`.
public func makeDedupeKey(
  date: Date,
  amountMinor: Int,
  directionRaw: String,
  normalizedDescription: String,
  calendar: Calendar = NomiCalendar.india
) -> String {
  let startOfDay = calendar.startOfDay(for: date)
  let iso = ISO8601DateFormatter()
  iso.formatOptions = [.withInternetDateTime]
  let raw = "\(iso.string(from: startOfDay))|\(amountMinor)|\(directionRaw)|\(normalizedDescription)"
  let digest = SHA256.hash(data: Data(raw.utf8))
  return digest.map { String(format: "%02x", $0) }.joined()
}

/// Glob matcher for `Rule.pattern`, e.g. `UPI-*AMAZON*`. `*` matches any run of
/// characters (including none); matching is case-sensitive against the caller's
/// already-normalized input.
///
/// **The prefix and the suffix are matched against disjoint spans (B4).**
/// Checking `hasPrefix` and `hasSuffix` independently let a single run of
/// characters satisfy both, so `*` could span a *negative* number of them:
/// `A*A` matched `A`, and `AB*BC` matched `ABC`. A rule asking for two
/// occurrences of something was satisfied by one, and silently categorised
/// rows it was written to exclude.
public func globMatches(pattern: String, value: String) -> Bool {
  let parts = pattern.components(separatedBy: "*")
  if parts.count == 1 {
    return value == pattern
  }

  let prefix = parts[0]
  let suffix = parts[parts.count - 1]

  // The length check is the fix. Everything below it was already correct given
  // that the two ends do not overlap.
  guard value.count >= prefix.count + suffix.count else { return false }
  guard prefix.isEmpty || value.hasPrefix(prefix) else { return false }
  guard suffix.isEmpty || value.hasSuffix(suffix) else { return false }

  // What is left for the middle parts to be found in: strictly between the two
  // ends, so a middle part cannot reach back into the prefix or forward into
  // the suffix either.
  let lower = value.index(value.startIndex, offsetBy: prefix.count)
  let upper = value.index(value.endIndex, offsetBy: -suffix.count)
  var remaining = value[lower..<upper]

  for part in parts.dropFirst().dropLast() where !part.isEmpty {
    guard let range = remaining.range(of: part) else { return false }
    remaining = remaining[range.upperBound...]
  }

  return true
}
