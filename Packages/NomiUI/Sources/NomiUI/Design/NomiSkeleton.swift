import SwiftUI

/// A loading placeholder shaped like the content it stands in for (F2a, I-17;
/// canvas States, "the shape of the content, not a spinner"). Each entry of
/// `lines` is a width as a fraction of the container. The first bar is 14 pt
/// high, the second 30 pt, and every later one 8 pt, all on `NomiColor.track`.
/// Decorative, so it is hidden from VoiceOver.
public struct NomiSkeleton: View {
  public let lines: [CGFloat]

  public init(lines: [CGFloat]) {
    self.lines = lines
  }

  private static func metrics(at index: Int) -> (height: CGFloat, radius: CGFloat) {
    switch index {
    case 0: return (14, 7)
    case 1: return (30, 10)
    default: return (8, 4)
    }
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      ForEach(Array(lines.enumerated()), id: \.offset) { index, fraction in
        let metric = Self.metrics(at: index)
        GeometryReader { proxy in
          HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: metric.radius, style: .continuous)
              .fill(NomiColor.track)
              .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            Spacer(minLength: 0)
          }
        }
        .frame(height: metric.height)
      }
    }
    .accessibilityHidden(true)
  }
}

#Preview("Skeleton") {
  NomiSkeleton(lines: [0.4, 0.62, 1])
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .nomiCard(padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
    .padding(20)
    .background(NomiColor.ground)
    .preferredColorScheme(.light)
}
