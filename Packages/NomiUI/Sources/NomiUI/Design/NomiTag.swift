// clt-harness: include
import SwiftUI

/// A small status word on a tone: 22 pt high, 8 pt side padding, micro
/// SemiBold 11 (F2a, I-17; canvas `.tag`). Neutral is `iconTile` with `navy`
/// text, warning is `warningTint` with `warning` text, error is `errorTint`
/// with `error` text. Every tone's text clears 4.5:1 on its fill.
///
/// The tag grows with Dynamic Type past 22 pt rather than clipping its word.
public struct NomiTag: View {
  public enum Tone: Sendable {
    case neutral
    case warning
    case error

    /// The fill as a hex token. The view reads the same token through `NomiColor`.
    var fillHex: UInt32 {
      switch self {
      case .neutral: return NomiHex.iconTile
      case .warning: return NomiHex.warningTint
      case .error: return NomiHex.errorTint
      }
    }

    /// The text as a hex token.
    var textHex: UInt32 {
      switch self {
      case .neutral: return NomiHex.navy
      case .warning: return NomiHex.warning
      case .error: return NomiHex.error
      }
    }
  }

  public let text: String
  public let tone: Tone
  /// Off by default: one line, truncated. On, the word wraps onto more lines
  /// instead of truncating. Used where a tag must never cut its copy at
  /// accessibility sizes (RemainingBudgetCard).
  public let wrapsText: Bool

  public init(_ text: String, tone: Tone = .neutral, wrapsText: Bool = false) {
    self.text = text
    self.tone = tone
    self.wrapsText = wrapsText
  }

  private var fill: Color {
    switch tone {
    case .neutral: return NomiColor.iconTile
    case .warning: return NomiColor.warningTint
    case .error: return NomiColor.errorTint
    }
  }

  private var textColor: Color {
    switch tone {
    case .neutral: return NomiColor.navy
    case .warning: return NomiColor.warning
    case .error: return NomiColor.error
    }
  }

  public var body: some View {
    Text(text)
      .font(.custom(NomiFont.interSemiBold, size: 11, relativeTo: .caption2))
      .foregroundStyle(textColor)
      .lineLimit(wrapsText ? nil : 1)
      .fixedSize(horizontal: false, vertical: wrapsText)
      .padding(.horizontal, 8)
      .frame(minHeight: 22)
      .background(Capsule().fill(fill))
  }
}

#Preview("Tags · tones") {
  HStack(spacing: 8) {
    NomiTag("Close", tone: .warning)
    NomiTag("Over", tone: .error)
    NomiTag("Recurring")
  }
  .padding(20)
  .frame(maxWidth: .infinity, alignment: .leading)
  .background(NomiColor.ground)
  .preferredColorScheme(.light)
}

#Preview("Tags · AX3") {
  VStack(alignment: .leading, spacing: 8) {
    NomiTag("Close", tone: .warning)
    NomiTag("Over", tone: .error)
  }
  .padding(20)
  .frame(maxWidth: .infinity, alignment: .leading)
  .background(NomiColor.ground)
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.light)
}
