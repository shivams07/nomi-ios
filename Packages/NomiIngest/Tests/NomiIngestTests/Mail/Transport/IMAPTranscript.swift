import Foundation
import XCTest

@testable import NomiIngest

/// A recorded IMAP dialogue, loaded off disk.
///
/// `#filePath`-relative rather than `Bundle.module`: the test target declares no
/// resources and must not — §2.10 grants U2 exactly one manifest line and U2b
/// none at all. Same route U3 and U2 already use for their fixtures.
struct IMAPTranscript {
  /// Client lines in order, without the trailing CRLF.
  let clientLines: [String]
  /// Server lines in order, without the trailing CRLF.
  let serverLines: [String]

  static func load(_ name: String) throws -> IMAPTranscript {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .appendingPathComponent("Transcripts")
      .appendingPathComponent(name)
    return parse(try String(contentsOf: url, encoding: .utf8))
  }

  static func parse(_ raw: String) -> IMAPTranscript {
    var client: [String] = []
    var server: [String] = []

    for line in raw.replacingOccurrences(of: "\r\n", with: "\n").split(
      separator: "\n", omittingEmptySubsequences: false)
    {
      let text = String(line)
      if text.hasPrefix("C: ") {
        client.append(String(text.dropFirst(3)))
      } else if text.hasPrefix("S: ") {
        server.append(String(text.dropFirst(3)))
      } else if text == "S:" {
        // A literal's blank line is content, not a separator.
        server.append("")
      }
    }
    return IMAPTranscript(clientLines: client, serverLines: server)
  }

  /// The bytes a server speaking this transcript would send, CRLF-terminated.
  var serverBytes: [UInt8] {
    Array(serverLines.map { $0 + "\r\n" }.joined().utf8)
  }
}
