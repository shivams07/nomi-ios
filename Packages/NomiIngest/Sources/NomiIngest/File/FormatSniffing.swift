import Foundation
import NomiCore

/// What a file actually is, independent of its extension. Many Indian bank
/// ".xls" downloads are HTML tables, not spreadsheets — see design R7.
enum SniffedFormat: Equatable {
  case csv
  case xlsx
  case htmlTable
  case legacyXLS
}

enum FormatSniffer {
  private static let zipMagic: [UInt8] = [0x50, 0x4B, 0x03, 0x04]
  private static let oleMagic: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]

  /// Content-sniffs `data`, ignoring the file extension entirely.
  /// Throws `.unreadableEncoding` if the bytes decode as neither CSV/HTML text
  /// nor a recognised binary spreadsheet container.
  static func sniff(data: Data) throws -> SniffedFormat {
    if data.count >= zipMagic.count, Array(data.prefix(zipMagic.count)) == zipMagic {
      return .xlsx
    }
    if data.count >= oleMagic.count, Array(data.prefix(oleMagic.count)) == oleMagic {
      return .legacyXLS
    }
    guard let text = TextDecoder.decode(data) else {
      throw ImportError.unreadableEncoding
    }
    let head = text
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    if head.hasPrefix("<html") || head.hasPrefix("<!doctype") || head.contains("<table") {
      return .htmlTable
    }
    return .csv
  }
}

/// Text decoding with a deliberately narrow support set. Real bank exports are
/// UTF-8 or UTF-16 (with BOM, from Excel "Save As"); anything outside that is
/// treated as unreadable rather than silently mojibake'd via a lossy fallback.
enum TextDecoder {
  static func decode(_ data: Data) -> String? {
    if data.starts(with: [0xFF, 0xFE]) {
      return String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
    }
    if data.starts(with: [0xFE, 0xFF]) {
      return String(data: data.dropFirst(2), encoding: .utf16BigEndian)
    }
    if data.starts(with: [0xEF, 0xBB, 0xBF]) {
      return String(data: data.dropFirst(3), encoding: .utf8)
    }
    return String(data: data, encoding: .utf8)
  }
}
