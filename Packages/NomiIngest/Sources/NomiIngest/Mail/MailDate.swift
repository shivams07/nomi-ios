import Foundation

/// Transaction dates out of mail text, with the `Date:` header as the fallback.
public enum MailDate {
  /// **Fixed at Asia/Kolkata, deliberately, and this is not a stylistic choice.**
  ///
  /// §1.5 requires `TransactionExtractor.extract` to be deterministic: identical
  /// input bytes must produce identical output on every device, forever, because
  /// the output feeds `dedupeKey`. A body date like `27-08-2026` carries no zone,
  /// so parsing it in `TimeZone.current` would give two of the user's devices two
  /// different instants for one email, two different `dedupeKey`s, and two rows
  /// that U4's reconcile pass cannot collapse — the same failure §1.5 argues
  /// Foundation Models would cause, reached by a different route.
  ///
  /// India is the whole target market (INR-only, Apr–Mar financial year) and
  /// Indian bank alerts are stamped IST, so IST is both the deterministic choice
  /// and the correct one.
  static let bankTimeZone = TimeZone(identifier: "Asia/Kolkata") ?? TimeZone(identifier: "UTC")!

  /// Format candidates are chosen by the SHAPE of the matched text, not tried
  /// blind in order.
  ///
  /// Blind iteration is how `2026-08-13` gets parsed as `dd-MM-yyyy` and yields
  /// a date in the year 13 — `DateFormatter` is happy to read `2026` as a day
  /// and the result is silently, plausibly wrong. Matching the shape first means
  /// a candidate is only ever offered to formats that could have produced it.
  private static let shapes: [(pattern: String, formats: [String])] = [
    (#"^\d{4}[-/]\d{1,2}[-/]\d{1,2}$"#, ["yyyy-MM-dd", "yyyy/MM/dd"]),
    (#"^\d{1,2}[-/.]\d{1,2}[-/.]\d{4}$"#, ["dd-MM-yyyy", "dd/MM/yyyy", "dd.MM.yyyy"]),
    (#"^\d{1,2}[-/.]\d{1,2}[-/.]\d{2}$"#, ["dd-MM-yy", "dd/MM/yy", "dd.MM.yy"]),
    (#"^\d{1,2}[- ][A-Za-z]{3,9}[- ]\d{4}$"#, ["dd-MMM-yyyy", "dd MMM yyyy"]),
    (#"^\d{1,2}[- ][A-Za-z]{3,9}[- ]\d{2}$"#, ["dd-MMM-yy", "dd MMM yy"]),
    (#"^[A-Za-z]{3,9} \d{1,2}, \d{4}$"#, ["MMM dd, yyyy", "MMMM dd, yyyy"]),
  ]

  private static func formatter(_ format: String) -> DateFormatter {
    let formatter = DateFormatter()
    // POSIX locale, or a device set to a non-Gregorian calendar parses "Aug"
    // differently — the same determinism argument as the time zone.
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = bankTimeZone
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = format
    formatter.isLenient = false
    return formatter
  }

  private static let candidatePattern =
    #"\b\d{1,2}[-/.]\d{1,2}[-/.]\d{2,4}\b"#
    + #"|\b\d{4}[-/]\d{1,2}[-/]\d{1,2}\b"#
    + #"|\b\d{1,2}[- ][A-Za-z]{3,9}[- ]\d{2,4}\b"#
    + #"|\b[A-Za-z]{3,9} \d{1,2}, \d{4}\b"#

  /// The first date-shaped run in the text that actually parses, scanning left
  /// to right — "the nearest parseable date" in §1.4's phrase. Bank alerts put
  /// the transaction date before the balance-as-of date, so first-wins is right
  /// far more often than last-wins.
  public static func firstDate(in text: String) -> Date? {
    guard let regex = try? NSRegularExpression(pattern: candidatePattern) else { return nil }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)

    for match in regex.matches(in: text, range: range) {
      guard let matched = Range(match.range, in: text) else { continue }
      let candidate = String(text[matched])
      if let date = parse(candidate) { return date }
    }
    return nil
  }

  /// One date string, shape-matched then parsed. Returns nil rather than
  /// guessing.
  static func parse(_ candidate: String) -> Date? {
    for shape in shapes {
      guard candidate.range(of: shape.pattern, options: .regularExpression) != nil else {
        continue
      }
      for format in shape.formats {
        if let date = formatter(format).date(from: candidate) { return date }
      }
    }
    return nil
  }

  /// RFC 5322 §4.3's obsolete zone names, mapped to the offset they mean.
  ///
  /// `DateFormatter`'s `Z` accepts a numeric offset and nothing else, so a
  /// header ending in `GMT` — which §4.3 makes perfectly legal, and which real
  /// senders still emit — parsed as nil and `RFC822Message` filed the message
  /// under 1 Jan 1970. That date reaches the ledger.
  ///
  /// The military single letters are deliberately absent apart from `Z`. §4.3
  /// records that they were implemented with the wrong sign in enough software
  /// that they must be treated as `-0000`, and `-0000` means "offset unknown".
  /// Guessing an instant from an unknown offset is how a transaction lands on
  /// the wrong day; a header carrying one still returns nil, still reaches the
  /// epoch fallback, and is now flagged for review because of it.
  private static let obsoleteZones: [String: String] = [
    "UT": "+0000", "GMT": "+0000", "Z": "+0000",
    "EST": "-0500", "EDT": "-0400",
    "CST": "-0600", "CDT": "-0500",
    "MST": "-0700", "MDT": "-0600",
    "PST": "-0800", "PDT": "-0700",
  ]

  /// RFC 5322 `Date:`. The header carries an explicit offset — numeric, or one
  /// of §4.3's names — so it is an unambiguous instant and needs no zone
  /// assumption.
  public static func parseHeaderDate(_ raw: String) -> Date? {
    var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    // Some senders append a zone name: "+0530 (IST)".
    if let paren = trimmed.firstIndex(of: "(") {
      trimmed = String(trimmed[..<paren]).trimmingCharacters(in: .whitespaces)
    }
    // A trailing zone NAME becomes the numeric offset before the formatter sees
    // it, rather than adding a `zzz` format: `zzz` parses against the current
    // locale's zone abbreviations, which is data that varies by platform and
    // would make this a different function on the CI runner than on a phone.
    if let lastSpace = trimmed.lastIndex(of: " ") {
      let zone = String(trimmed[trimmed.index(after: lastSpace)...]).uppercased()
      if let offset = obsoleteZones[zone] {
        trimmed = String(trimmed[..<lastSpace]) + " " + offset
      }
    }

    let formats = [
      "EEE, d MMM yyyy HH:mm:ss Z",
      "d MMM yyyy HH:mm:ss Z",
      "EEE, d MMM yyyy HH:mm Z",
      "d MMM yyyy HH:mm Z",
    ]
    for format in formats {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.dateFormat = format
      if let date = formatter.date(from: trimmed) { return date }
    }
    return nil
  }
}
