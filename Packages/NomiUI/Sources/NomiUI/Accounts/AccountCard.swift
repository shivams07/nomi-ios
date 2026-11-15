import NomiCore
import SwiftUI

/// One account as a physical card (S8 step 2, the Accounts artboard). 150 pt high
/// at the default sizes. At accessibility sizes the height is free, every line
/// wraps, and the bottom row stacks (D12). The whole card is one VoiceOver element.
struct AccountCard: View {
  let account: AccountSummary
  let action: () -> Void

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  private var kind: AccountKind { AccountKindOptions.kind(raw: account.kindRaw) }
  private var style: NomiAccountCardStyle { NomiAccountCardStyle.of(kind: kind) }
  private var balance: AccountBalanceDisplay.Line {
    AccountBalanceDisplay.line(kind: kind, trackedMinor: account.trackedBalanceMinor)
  }
  private var foreground: Color { Color(hex: style.foregroundHex) }

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 0) {
        topRow
        Spacer(minLength: NomiSpacing.cardGap)
        bottomRow
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 16)
      .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 0 : 150, alignment: .leading)
      .background { NomiAccountCardBackground(style: style) }
      .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
      .foregroundStyle(foreground)
      .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      AccountCardAccessibility.label(
        displayName: account.displayName,
        lastFour: account.lastFour,
        kind: kind,
        trackedMinor: account.trackedBalanceMinor
      )
    )
    .accessibilityAddTraits(.isButton)
  }

  /// The title and its second line, with the tile or the chip at the trailing edge.
  private var topRow: some View {
    HStack(alignment: .top, spacing: NomiSpacing.sm) {
      VStack(alignment: .leading, spacing: 2) {
        Text(AccountCardText.title(institution: account.institution, displayName: account.displayName))
          .font(.custom(NomiFont.interSemiBold, size: 16, relativeTo: .body))
        Text(AccountCardText.subtitle(institution: account.institution, displayName: account.displayName, kind: kind))
          .font(.custom(NomiFont.interMedium, size: 12, relativeTo: .caption))
          .opacity(0.85)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .layoutPriority(1)

      if style == .paper {
        AccountTile(symbolName: AccountTileSymbol.name(for: kind))
      } else {
        NomiEMVChip()
      }
    }
  }

  /// The count and the masked last four on the left, the balance on the right. At
  /// accessibility sizes the two stack, and the balance sits under the identity.
  private var bottomRow: some View {
    let stacked = dynamicTypeSize.isAccessibilitySize
    return Group {
      if stacked {
        VStack(alignment: .leading, spacing: NomiSpacing.xs) {
          identity
          amount(alignment: .leading)
        }
      } else {
        HStack(alignment: .bottom, spacing: NomiSpacing.sm) {
          identity
          Spacer(minLength: 0)
          amount(alignment: .trailing)
        }
      }
    }
  }

  private var identity: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(String(localized: "\(account.transactionCount) transactions", bundle: .module))
        .font(.custom(NomiFont.interMedium, size: 12, relativeTo: .caption))
        .opacity(0.85)
      if let masked = AccountCardText.lastFourLine(account.lastFour) {
        Text(masked)
          .font(.custom(NomiFont.interMedium, size: 14, relativeTo: .body))
          .monospacedDigit()
          .tracking(2)
      }
    }
  }

  private func amount(alignment: HorizontalAlignment) -> some View {
    VStack(alignment: alignment, spacing: 2) {
      if balance.caption != nil {
        Text("Owed")
          .font(.custom(NomiFont.interMedium, size: 12, relativeTo: .caption))
          .opacity(0.85)
      }
      AccountAmountLabel(minor: balance.minor, size: 24, color: foreground)
    }
  }
}

/// A card amount: the integer at `size`, the decimals at half opacity, in Inter
/// SemiBold with monospaced digits. Its own view because the design system has no
/// 24 or 38 pt amount style and `NomiAmountText` cannot take a card's colour.
struct AccountAmountLabel: View {
  let minor: Int
  let size: CGFloat
  let color: Color

  var body: some View {
    let parts = NomiAmountFormat.parts(minor: minor)
    (Text(parts.sign + parts.integer).foregroundStyle(color)
      + Text(parts.decimals).foregroundStyle(color.opacity(0.5)))
      .font(.custom(NomiFont.interSemiBold, size: size, relativeTo: .title2))
      .monospacedDigit()
      .lineLimit(1)
      .minimumScaleFactor(0.5)
      .accessibilityHidden(true)
  }
}
