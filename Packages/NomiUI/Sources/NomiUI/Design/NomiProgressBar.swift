// clt-harness: include
import SwiftUI

/// The shared budget progress bar. U9's dashboard module and U12's budgets
/// list both depend on this existing here. If the two built their own they
/// would diverge, and this file exists to stop that.
///
/// 6 points high on `NomiColor.track`, filled in `NomiColor.navy`. At or above
/// 90% the fill switches to `NomiColor.error`, the one error red (SIMP §5).
/// Over-budget is also signalled in words and by a glyph elsewhere, so colour
/// is never the only signal.
public struct NomiProgressBar: View {
  public let fraction: Double

  public init(fraction: Double) {
    self.fraction = fraction
  }

  private var clamped: Double {
    min(max(fraction, 0), 1)
  }

  private var isOverBudget: Bool {
    fraction >= 0.9
  }

  var clampedForTesting: Double { clamped }
  var isOverBudgetForTesting: Bool { isOverBudget }

  public var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule(style: .continuous)
          .fill(NomiColor.track)
        Capsule(style: .continuous)
          .fill(isOverBudget ? NomiColor.error : NomiColor.navy)
          .frame(width: proxy.size.width * clamped)
      }
    }
    .frame(height: 6)
    .clipShape(Capsule(style: .continuous))
  }
}

#Preview("0%, 89%, 90%, 100%, 140%") {
  VStack(spacing: NomiSpacing.sm) {
    ForEach([0.0, 0.89, 0.90, 1.0, 1.4], id: \.self) { fraction in
      NomiProgressBar(fraction: fraction)
    }
  }
  .padding()
  .background(NomiColor.ground)
  .preferredColorScheme(.light)
}
