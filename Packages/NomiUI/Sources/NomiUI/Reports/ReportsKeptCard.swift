import Foundation
import NomiCore
import SwiftUI

/// What the period kept: credit minus debit over the counted rows (S6). It is
/// the same pair of figures the tiles show, so no new read.
enum ReportsKept {
  static func minor(creditMinor: Int, debitMinor: Int) -> Int {
    creditMinor - debitMinor
  }

  /// The kept share of income, "8%" or "−12%", rounded. `nil` when no income is
  /// recorded, which the card words itself.
  static func percentText(keptMinor: Int, creditMinor: Int) -> String? {
    guard creditMinor > 0 else { return nil }
    let percent = Int((Double(keptMinor) / Double(creditMinor) * 100).rounded())
    return percent < 0 ? "\u{2212}\(abs(percent))%" : "\(percent)%"
  }

  /// The Kept figure's colour. Navy from zero up, ink below zero (the spec's
  /// rule: navy with "+" when >= 0, ink with "−" when < 0).
  static func amountColour(keptMinor: Int) -> Color {
    keptMinor < 0 ? NomiColor.ink : NomiColor.navy
  }
}

/// "Kept this month" or "Kept this year" (S6). The amount is credit minus debit
/// in `navy`, with "+" from zero up and "−" below it. The caption gives the
/// share of income and notes that transfers are not counted.
struct ReportsKeptCard: View {
  let isMonth: Bool
  let keptMinor: Int
  let creditMinor: Int

  init(isMonth: Bool, keptMinor: Int, creditMinor: Int) {
    self.isMonth = isMonth
    self.keptMinor = keptMinor
    self.creditMinor = creditMinor
  }

  private var title: LocalizedStringKey {
    isMonth ? "Kept this month" : "Kept this year"
  }

  var body: some View {
    HStack(alignment: .center, spacing: NomiSpacing.xs) {
      VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
        Text(title, bundle: .module)
          .nomiTextStyle(.subhead)
          .foregroundStyle(NomiColor.inkSecondary)
        amountText
          .lineLimit(1)
          .minimumScaleFactor(0.6)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      caption
        .multilineTextAlignment(.trailing)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .nomiCard(padding: EdgeInsets(top: NomiSpacing.sm, leading: NomiSpacing.sm, bottom: NomiSpacing.sm, trailing: NomiSpacing.sm))
    .accessibilityElement(children: .combine)
  }

  /// The amount in one line: sign, integer, then the dimmed decimals. Navy from
  /// zero up, ink below zero. `NomiAmountText` draws ink only, so the figure is
  /// set here from the same parts.
  private var amountText: Text {
    let parts = NomiAmountFormat.parts(minor: abs(keptMinor))
    let sign = keptMinor < 0 ? "\u{2212}" : "+"
    let style = NomiTextStyle.amountLarge
    let colour = ReportsKept.amountColour(keptMinor: keptMinor)
    return Text(sign + parts.integer)
      .font(style.font)
      .foregroundStyle(colour)
      + Text(parts.decimals)
      .font(style.font)
      .foregroundStyle(colour.opacity(NomiAmountText.decimalsOpacity(for: style)))
  }

  @ViewBuilder
  private var caption: some View {
    VStack(alignment: .trailing, spacing: 2) {
      if let percent = ReportsKept.percentText(keptMinor: keptMinor, creditMinor: creditMinor) {
        Text(verbatim: String(localized: "\(percent) of income", bundle: .module))
        Text("Transfers not counted", bundle: .module)
      } else {
        Text("No income recorded", bundle: .module)
      }
    }
    .nomiTextStyle(.caption)
    .foregroundStyle(NomiColor.inkSecondary)
  }
}
