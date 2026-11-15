// clt-harness: include
import SwiftUI

/// The shared budget progress bar. U9's dashboard module and U12's budgets
/// list both depend on this existing here. If the two built their own they
/// would diverge, and this file exists to stop that.
///
/// `height` points high (8 by default) on `NomiColor.track`, radius 4. The
/// fill follows `state`: under is `navy`, close is `warningFill`, over is
/// `error`. A close or over bar is also labelled by a tag, so colour is never
/// the only signal. On a hero (`onHero`) the track is white at 30%, the fill
/// is white, and `state` is ignored.
public struct NomiProgressBar: View {
  public let fraction: Double
  public let state: NomiBudgetState
  public let height: CGFloat
  public let onHero: Bool

  public init(fraction: Double, state: NomiBudgetState = .under, height: CGFloat = 8, onHero: Bool = false) {
    self.fraction = fraction
    self.state = state
    self.height = height
    self.onHero = onHero
  }

  /// The pre-F2a call. Maps the fraction onto the three states (over from
  /// 100%, close from 90%), so BudgetsScreen and Home compile unchanged.
  public init(fraction: Double) {
    self.init(fraction: fraction, state: fraction >= 1 ? .over : fraction >= 0.9 ? .close : .under)
  }

  private var clamped: Double {
    min(max(fraction, 0), 1)
  }

  private var fillColor: Color {
    if onHero { return NomiColor.heroText }
    switch state {
    case .under: return NomiColor.navy
    case .close: return NomiColor.warningFill
    case .over: return NomiColor.error
    }
  }

  private var trackColor: Color {
    onHero ? NomiColor.heroText.opacity(0.30) : NomiColor.track
  }

  var clampedForTesting: Double { clamped }

  /// The fill's token as hex, mirroring `fillColor`, for tests.
  var fillHexForTesting: UInt32 {
    if onHero { return NomiHex.white }
    switch state {
    case .under: return NomiHex.navy
    case .close: return NomiHex.warningFill
    case .over: return NomiHex.error
    }
  }

  public var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .fill(trackColor)
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .fill(fillColor)
          .frame(width: proxy.size.width * clamped)
      }
    }
    .frame(height: height)
  }
}

#Preview("Under, close and over") {
  VStack(spacing: NomiSpacing.sm) {
    NomiProgressBar(fraction: 0.5, state: .under)
    NomiProgressBar(fraction: 0.95, state: .close)
    NomiProgressBar(fraction: 1.1, state: .over)
    NomiProgressBar(fraction: 0.6, onHero: true)
  }
  .padding()
  .background(NomiColor.ground)
  .preferredColorScheme(.light)
}
