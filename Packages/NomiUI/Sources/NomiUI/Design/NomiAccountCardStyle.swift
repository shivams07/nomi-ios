import NomiCore
import SwiftUI

/// The three looks of an account card on the Accounts screen (S8, nomi.css
/// `.pcard`): a bank is moss, a card is black, a wallet is paper. The raw colours
/// live in this file because `Design/` is where G1 allows them.
enum NomiAccountCardStyle: Equatable, CaseIterable {
  case moss
  case black
  case paper

  static func of(kind: AccountKind) -> NomiAccountCardStyle {
    switch kind {
    case .bank: return .moss
    case .card: return .black
    case .wallet: return .paper
    }
  }

  /// The 135-degree gradient, in the order the canvas runs its stops. Paper has none.
  var gradientStops: [UInt32] {
    switch self {
    case .moss: return [0x22392A, 0x3C5A38, 0x587C50]
    case .black: return [0x232723, 0x0C0F0C, 0x1A1D1A]
    case .paper: return []
    }
  }

  /// Locations for `gradientStops`: the canvas's 0%, 55% and 100%.
  static let gradientLocations: [CGFloat] = [0, 0.55, 1]

  /// White on the two dark looks, ink on paper.
  var foregroundHex: UInt32 {
    switch self {
    case .moss, .black: return 0xFFFFFF
    case .paper: return 0x111411
    }
  }
}

/// A card's background: the gradient with its sheen band for moss and black,
/// a card fill with a hairline for paper.
struct NomiAccountCardBackground: View {
  let style: NomiAccountCardStyle

  var body: some View {
    switch style {
    case .moss, .black:
      ZStack {
        LinearGradient(
          stops: zip(style.gradientStops, NomiAccountCardStyle.gradientLocations).map { hex, location in
            Gradient.Stop(color: Color(hex: hex), location: location)
          },
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        // The sheen: a white band 150 x 340 pt, rotated 28 degrees, offset from the top-trailing corner.
        Rectangle()
          .fill(
            LinearGradient(
              colors: [.white.opacity(0), .white.opacity(0.11), .white.opacity(0)],
              startPoint: .leading,
              endPoint: .trailing
            )
          )
          .frame(width: 150, height: 340)
          .rotationEffect(.degrees(28))
          .offset(x: 30, y: -80)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
          .clipped()
      }
    case .paper:
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .fill(NomiColor.card)
        .overlay(
          RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(NomiColor.separator, lineWidth: 1)
        )
    }
  }
}

/// The 34 x 25 pt EMV chip on a bank or card, drawn from the canvas `.emv`.
struct NomiEMVChip: View {
  var body: some View {
    RoundedRectangle(cornerRadius: 6, style: .continuous)
      .fill(
        LinearGradient(
          colors: [Color(hex: 0xEADCAE), Color(hex: 0xB89A4F)],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
      .frame(width: 34, height: 25)
      .accessibilityHidden(true)
  }
}
