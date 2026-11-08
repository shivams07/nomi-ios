import Foundation
import SwiftUI

// clt-harness: include

/// Lays the entry sheet's chips out in lines, left to right, wrapping to the
/// next line when a chip would not fit. A chip is never truncated: one wider
/// than the proposal sits alone on its line. The line breaks come from
/// `EntryChipFlow.lines`, which is pure and tested without a view.
struct EntryChipFlowLayout: Layout {
  var spacing: CGFloat = 8

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    let available = proposal.width ?? .greatestFiniteMagnitude
    let lines = EntryChipFlow.lines(widths: sizes.map(\.width), available: available, spacing: spacing)

    var height: CGFloat = 0
    var widest: CGFloat = 0
    for (lineIndex, line) in lines.enumerated() {
      if lineIndex > 0 { height += spacing }
      height += line.map { sizes[$0].height }.max() ?? 0
      let gaps = spacing * CGFloat(max(line.count - 1, 0))
      widest = max(widest, line.reduce(CGFloat(0)) { $0 + sizes[$1].width } + gaps)
    }
    return CGSize(width: proposal.width ?? widest, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    let lines = EntryChipFlow.lines(widths: sizes.map(\.width), available: bounds.width, spacing: spacing)

    var y = bounds.minY
    for line in lines {
      let lineHeight = line.map { sizes[$0].height }.max() ?? 0
      var x = bounds.minX
      for index in line {
        subviews[index].place(
          at: CGPoint(x: x, y: y),
          anchor: .topLeading,
          proposal: ProposedViewSize(sizes[index])
        )
        x += sizes[index].width + spacing
      }
      y += lineHeight + spacing
    }
  }
}

/// The greedy line break behind `EntryChipFlowLayout`. `widths` are the chips'
/// natural widths in order; the result lists the indices on each line, in order.
/// Empty input gives no lines.
enum EntryChipFlow {
  static func lines(widths: [CGFloat], available: CGFloat, spacing: CGFloat) -> [[Int]] {
    var result: [[Int]] = []
    var current: [Int] = []
    var currentWidth: CGFloat = 0

    for (index, width) in widths.enumerated() {
      if current.isEmpty {
        current = [index]
        currentWidth = width
      } else if currentWidth + spacing + width <= available {
        current.append(index)
        currentWidth += spacing + width
      } else {
        result.append(current)
        current = [index]
        currentWidth = width
      }
    }
    if !current.isEmpty {
      result.append(current)
    }
    return result
  }
}

#Preview("Chip flow · wraps · light") {
  EntryChipFlowLayout(spacing: NomiSpacing.xs) {
    ForEach(["Food & Dining", "HDFC Savings", "Today", "Bills & Utilities"], id: \.self) { title in
      Text(title)
        .font(.custom(NomiFont.interMedium, size: 15, relativeTo: .body))
        .padding(.horizontal, NomiSpacing.sm)
        .frame(minHeight: NomiSpacing.minTarget)
        .background(Capsule().fill(NomiColor.card))
    }
  }
  .padding(NomiSpacing.screenGutter)
  .frame(width: 330, alignment: .leading)
  .background(NomiColor.ground)
  .preferredColorScheme(.light)
}
