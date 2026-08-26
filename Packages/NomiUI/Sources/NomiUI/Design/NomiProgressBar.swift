import SwiftUI

/// The shared budget progress bar. U9's dashboard module and U12's budgets
/// list both depend on this existing here — if the two built their own they
/// would diverge, and this file exists to stop that.
///
/// `#2388FF` (DB-24) is the one progress-track fill in the system, used only
/// here. At or above 90% the fill switches to `NomiColor.overBudget` — the
/// category-palette red slot at chip scale, distinct from the destructive/
/// error red Estate-Ease reserves elsewhere.
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
          .fill(NomiColor.surface)
        Capsule(style: .continuous)
          .fill(isOverBudget ? NomiColor.overBudget : NomiColor.progressTrackFill)
          .frame(width: proxy.size.width * clamped)
      }
    }
    .frame(height: NomiSpacing.xs)
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
  .background(NomiColor.surfaceRaised)
  .preferredColorScheme(.dark)
}
