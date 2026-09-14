import SwiftUI

/// The circular counterpart to `NomiProgressBar` — same clamp, same 90%
/// `overBudget` threshold, same track/fill tokens, so the ring and the bars
/// can never disagree. `v5` (`nomi-ui-refresh`) Budgets gauge card.
/// Stroke-based `Circle().trim(...)`, no Charts framework dependency.
public struct NomiRingGauge: View {
  public let fraction: Double
  public let lineWidth: CGFloat

  public init(fraction: Double, lineWidth: CGFloat = 12) {
    self.fraction = fraction
    self.lineWidth = lineWidth
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
    ZStack {
      Circle()
        .stroke(NomiColor.surface, lineWidth: lineWidth)
      Circle()
        .trim(from: 0, to: clamped)
        .stroke(
          isOverBudget ? NomiColor.overBudget : NomiColor.progressTrackFill,
          style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        )
        .rotationEffect(.degrees(-90))
    }
  }
}

#Preview("0.4, 0.9, 1.3") {
  HStack(spacing: NomiSpacing.sm) {
    ForEach([0.4, 0.9, 1.3], id: \.self) { fraction in
      NomiRingGauge(fraction: fraction)
        .frame(width: 120, height: 120)
    }
  }
  .padding()
  .background(NomiColor.surfaceRaised)
  .preferredColorScheme(.dark)
}
