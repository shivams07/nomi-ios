import CryptoKit
import Foundation

/// Signature of a file's header row — the key both `ColumnMappingRecord` and
/// bank-preset detection index on. Same signature => same "shape", whether
/// it's a saved custom mapping or a provisional preset.
enum FormatSignature {
  static func make(headers: [String]) -> String {
    let normalized = headers
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
      .joined(separator: "|")
    let digest = SHA256.hash(data: Data(normalized.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }
}
