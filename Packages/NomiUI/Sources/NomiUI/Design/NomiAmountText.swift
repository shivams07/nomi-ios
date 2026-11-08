import SwiftUI

// clt-harness: include

/// An amount split for typesetting: `sign` is "", "−" (U+2212) or "+", and
/// `decimals` is "" when the currency has none (JPY).
public struct NomiAmountParts: Equatable, Sendable {
  public let sign: String
  public let integer: String
  public let decimals: String

  public init(sign: String, integer: String, decimals: String) {
    self.sign = sign
    self.integer = integer
    self.decimals = decimals
  }
}

public enum NomiAmountFormat {
  /// Splits `minor` (paise, cents, yen) into sign, integer and decimals.
  ///
  /// The sign is "−" if `minor` is negative, "+" if `showPlus` and `minor` is
  /// positive, and "" otherwise. The integer and decimals come from
  /// `NomiFormatters.amountString`, split at its last ".". With no ".", the
  /// decimals are "".
  public static func parts(minor: Int, currencyCode: String = "INR", showPlus: Bool = false) -> NomiAmountParts {
    let sign: String
    if minor < 0 {
      sign = "\u{2212}"
    } else if showPlus && minor > 0 {
      sign = "+"
    } else {
      sign = ""
    }

    let formatted = NomiFormatters.amountString(minor: minor, currencyCode: currencyCode)
    guard let dot = formatted.lastIndex(of: ".") else {
      return NomiAmountParts(sign: sign, integer: formatted, decimals: "")
    }
    return NomiAmountParts(
      sign: sign,
      integer: String(formatted[..<dot]),
      decimals: String(formatted[dot...])
    )
  }
}

/// An amount in one line. The decimals are dimmed (SIMP §1 rule 4):
/// `decimalOpacityGround` on the ground, `decimalOpacityHero` on the hero.
/// The text shrinks to half size before it wraps, and the whole amount is one
/// accessibility element.
public struct NomiAmountText: View {
  public enum Context: Sendable {
    case ground
    case hero
  }

  public let minor: Int
  public let currencyCode: String
  public let showPlus: Bool
  public let context: Context
  public let style: NomiTextStyle
  public let accessibilityLabel: String?

  public init(
    minor: Int,
    currencyCode: String = "INR",
    showPlus: Bool = false,
    context: Context = .ground,
    style: NomiTextStyle,
    accessibilityLabel: String? = nil
  ) {
    self.minor = minor
    self.currencyCode = currencyCode
    self.showPlus = showPlus
    self.context = context
    self.style = style
    self.accessibilityLabel = accessibilityLabel
  }

  private var parts: NomiAmountParts {
    NomiAmountFormat.parts(minor: minor, currencyCode: currencyCode, showPlus: showPlus)
  }

  private var primaryColor: Color {
    context == .hero ? NomiColor.heroText : NomiColor.ink
  }

  private var decimalColor: Color {
    switch context {
    case .ground:
      return NomiColor.ink.opacity(NomiColor.decimalOpacityGround)
    case .hero:
      return NomiColor.heroText.opacity(NomiColor.decimalOpacityHero)
    }
  }

  public var body: some View {
    let amount = parts
    (Text(amount.sign + amount.integer)
      .font(style.font)
      .tracking(style.tracking)
      .foregroundStyle(primaryColor)
      + Text(amount.decimals)
      .font(style.font)
      .tracking(style.tracking)
      .foregroundStyle(decimalColor))
      .lineLimit(1)
      .minimumScaleFactor(0.5)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(accessibilityLabel ?? (amount.sign + amount.integer + amount.decimals))
  }
}

#Preview("Amount · ground and hero · default") {
  VStack(alignment: .leading, spacing: 16) {
    NomiAmountText(minor: -6_482_424, style: .amount)
    NomiAmountText(minor: 3_850_000, showPlus: true, style: .amountStrong)
    NomiAmountText(minor: 13_327_950, context: .hero, style: .heroAmount)
      .padding(20)
      .background(NomiHeroGradient.gradient(height: 200, safeTop: 54))
  }
  .padding(20)
  .frame(maxWidth: .infinity, alignment: .leading)
  .background(NomiColor.ground)
  .preferredColorScheme(.light)
}

#Preview("Amount · ground and hero · AX3") {
  VStack(alignment: .leading, spacing: 16) {
    NomiAmountText(minor: -6_482_424, style: .amount)
    NomiAmountText(minor: 3_850_000, showPlus: true, style: .amountStrong)
    NomiAmountText(minor: 13_327_950, context: .hero, style: .heroAmount)
      .padding(20)
      .background(NomiHeroGradient.gradient(height: 200, safeTop: 54))
  }
  .padding(20)
  .frame(maxWidth: .infinity, alignment: .leading)
  .background(NomiColor.ground)
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.light)
}
