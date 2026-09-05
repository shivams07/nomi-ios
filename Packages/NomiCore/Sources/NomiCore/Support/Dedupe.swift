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
public func globMatches(pattern: String, value: String) -> Bool {
  let parts = pattern.components(separatedBy: "*")
  if parts.count == 1 {
    return value == pattern
  }

  var searchStart = value.startIndex

  if let first = parts.first, !first.isEmpty {
    guard value.hasPrefix(first) else { return false }
    searchStart = value.index(value.startIndex, offsetBy: first.count)
  }

  if let last = parts.last, !last.isEmpty {
    guard value.hasSuffix(last) else { return false }
  }

  let middleParts = parts.dropFirst().dropLast()
  var remaining = value[searchStart...]
  if let last = parts.last, !last.isEmpty {
    remaining = remaining.dropLast(last.count)
  }

  for part in middleParts where !part.isEmpty {
    guard let range = remaining.range(of: part) else { return false }
    remaining = remaining[range.upperBound...]
  }

  return true
}
