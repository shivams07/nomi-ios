import Foundation

/// RFC 5322 bytes -> `MailMessage`.
///
/// One parser, two callers: the IMAP transport hands it a `FETCH BODY.PEEK[]`
/// payload, and the fixture tests hand it a `.eml` file. That is deliberate —
/// it means a real saved message from the user's mailbox exercises the exact
/// code path production uses, with no adapter in between (§2.5.2).
public enum RFC822Message {
  public enum ParseError: Error, Sendable, Equatable {
    case undecodableBytes
  }

  public static func parse(
    _ data: Data, uid: UInt32, uidValidity: UInt32, mailboxName: String = "INBOX"
  ) throws -> MailMessage {
    guard
      let raw = String(data: data, encoding: .utf8)
        ?? String(data: data, encoding: .isoLatin1)
    else { throw ParseError.undecodableBytes }
    return parse(raw, uid: uid, uidValidity: uidValidity, mailboxName: mailboxName)
  }

  public static func parse(
    _ raw: String, uid: UInt32, uidValidity: UInt32, mailboxName: String = "INBOX"
  ) -> MailMessage {
    let (headers, body) = splitHeadersAndBody(raw)
    let parts = decodeParts(headers: headers, body: body)

    return MailMessage(
      uid: uid,
      uidValidity: uidValidity,
      mailboxName: mailboxName,
      fromRaw: decodeEncodedWords(headers["from"] ?? ""),
      subject: decodeEncodedWords(headers["subject"] ?? ""),
      // Epoch, not `Date()`, when the header is missing or unreadable: this
      // value can end up as a transaction date, and "now" would silently file a
      // broken message under today.
      headerDate: MailDate.parseHeaderDate(headers["date"] ?? "")
        ?? Date(timeIntervalSince1970: 0),
      htmlBody: parts.html,
      textBody: parts.text
    )
  }

  // MARK: - Headers

  /// Lowercased names, unfolded values. A duplicate header keeps the first,
  /// which is what every mail client does.
  static func splitHeadersAndBody(_ raw: String) -> (headers: [String: String], body: String) {
    let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
    guard let separator = normalized.range(of: "\n\n") else {
      return (parseHeaderBlock(normalized), "")
    }
    return (
      parseHeaderBlock(String(normalized[..<separator.lowerBound])),
      String(normalized[separator.upperBound...])
    )
  }

  private static func parseHeaderBlock(_ block: String) -> [String: String] {
    var headers: [String: String] = [:]
    var currentName: String?
    var currentValue = ""

    func flush() {
      if let name = currentName, headers[name] == nil {
        headers[name] = currentValue.trimmingCharacters(in: .whitespaces)
      }
      currentName = nil
      currentValue = ""
    }

    for line in block.split(separator: "\n", omittingEmptySubsequences: false) {
      // A folded continuation starts with whitespace and belongs to the header
      // above it.
      if let first = line.first, first == " " || first == "\t", currentName != nil {
        currentValue += " " + line.trimmingCharacters(in: .whitespaces)
        continue
      }
      flush()
      guard let colon = line.firstIndex(of: ":") else { continue }
      currentName = String(line[..<colon]).lowercased().trimmingCharacters(in: .whitespaces)
      currentValue = String(line[line.index(after: colon)...])
    }
    flush()
    return headers
  }

  // MARK: - Bodies

  private static func decodeParts(
    headers: [String: String], body: String
  ) -> (html: String?, text: String?) {
    let contentType = headers["content-type"] ?? "text/plain"

    if let boundary = parameter("boundary", in: contentType) {
      return walkMultipart(body, boundary: boundary)
    }

    let decoded = decodeTransfer(body, encoding: headers["content-transfer-encoding"])
    if contentType.lowercased().contains("text/html") {
      return (decoded, nil)
    }
    return (nil, decoded)
  }

  /// Recurses, because `multipart/mixed` wrapping `multipart/alternative` is the
  /// normal shape for a bank alert carrying a logo attachment.
  private static func walkMultipart(
    _ body: String, boundary: String
  ) -> (html: String?, text: String?) {
    var html: String?
    var text: String?

    let segments = body.components(separatedBy: "--" + boundary)
    for segment in segments.dropFirst() {
      // The closing delimiter is "--boundary--", so a segment starting with "--"
      // is the epilogue.
      guard !segment.hasPrefix("--") else { continue }
      let trimmed = segment.trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))
      guard !trimmed.isEmpty else { continue }

      let (partHeaders, partBody) = splitHeadersAndBody(trimmed)
      let partType = (partHeaders["content-type"] ?? "text/plain").lowercased()

      if let nested = parameter("boundary", in: partType) {
        let inner = walkMultipart(partBody, boundary: nested)
        html = html ?? inner.html
        text = text ?? inner.text
        continue
      }

      let decoded = decodeTransfer(partBody, encoding: partHeaders["content-transfer-encoding"])
      if partType.contains("text/html") {
        html = html ?? decoded
      } else if partType.contains("text/plain") {
        text = text ?? decoded
      }
    }
    return (html, text)
  }

  static func decodeTransfer(_ body: String, encoding: String?) -> String {
    switch (encoding ?? "7bit").lowercased().trimmingCharacters(in: .whitespaces) {
    case "quoted-printable":
      return decodeQuotedPrintable(body)
    case "base64":
      let joined = body.components(separatedBy: .whitespacesAndNewlines).joined()
      guard let data = Data(base64Encoded: joined, options: [.ignoreUnknownCharacters]),
        let decoded = String(data: data, encoding: .utf8)
      else { return body }
      return decoded
    default:
      return body
    }
  }

  static func decodeQuotedPrintable(_ raw: String) -> String {
    // Soft line breaks first, or "=\n" splits a multi-byte UTF-8 sequence and
    // the rupee sign comes out as three replacement characters.
    let unwrapped = raw.replacingOccurrences(of: "=\r\n", with: "")
      .replacingOccurrences(of: "=\n", with: "")

    var bytes: [UInt8] = []
    var index = unwrapped.startIndex
    while index < unwrapped.endIndex {
      let character = unwrapped[index]
      // offsetBy 3, because "=4A" is three characters and the hex range below is
      // index+1 ..< index+3. Bounded, or a body ending in a bare "=" traps.
      if character == "=",
        let hexEnd = unwrapped.index(index, offsetBy: 3, limitedBy: unwrapped.endIndex)
      {
        let hexStart = unwrapped.index(after: index)
        if let byte = UInt8(unwrapped[hexStart..<hexEnd], radix: 16) {
          bytes.append(byte)
          index = hexEnd
          continue
        }
      }
      bytes.append(contentsOf: Array(String(character).utf8))
      index = unwrapped.index(after: index)
    }
    return String(decoding: bytes, as: UTF8.self)
  }

  // MARK: -

  /// RFC 2047 `=?UTF-8?B?…?=` / `=?UTF-8?Q?…?=`, which is how a subject line
  /// carrying a ₹ arrives.
  static func decodeEncodedWords(_ raw: String) -> String {
    guard raw.contains("=?"),
      let regex = try? NSRegularExpression(
        pattern: #"=\?([^?]+)\?([BbQq])\?([^?]*)\?="#, options: [])
    else { return raw }

    var result = raw
    let matches = regex.matches(in: raw, range: NSRange(raw.startIndex..<raw.endIndex, in: raw))
    // Reversed, so replacing one encoded word does not shift the ranges of the
    // ones still to be replaced.
    for match in matches.reversed() {
      guard let whole = Range(match.range, in: result),
        let kindRange = Range(match.range(at: 2), in: raw),
        let payloadRange = Range(match.range(at: 3), in: raw)
      else { continue }

      let payload = String(raw[payloadRange])
      let decoded: String?
      if raw[kindRange].lowercased() == "b" {
        decoded = Data(base64Encoded: payload, options: [.ignoreUnknownCharacters])
          .flatMap { String(data: $0, encoding: .utf8) }
      } else {
        decoded = decodeQuotedPrintable(payload.replacingOccurrences(of: "_", with: " "))
      }
      if let decoded {
        result.replaceSubrange(whole, with: decoded)
      }
    }
    return result
  }

  private static func parameter(_ name: String, in headerValue: String) -> String? {
    guard
      let regex = try? NSRegularExpression(
        pattern: name + #"\s*=\s*"?([^";\s]+)"?"#, options: [.caseInsensitive]),
      let match = regex.firstMatch(
        in: headerValue,
        range: NSRange(headerValue.startIndex..<headerValue.endIndex, in: headerValue)),
      match.numberOfRanges > 1,
      let range = Range(match.range(at: 1), in: headerValue)
    else { return nil }
    return String(headerValue[range])
  }
}
