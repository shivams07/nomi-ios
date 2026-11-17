// clt-harness: include
import Testing
@testable import NomiUI

/// NomiTag (F2a, I-17). Each tone's text on its own fill passes 4.5:1, so the
/// tag's words carry the state and the colour is never the only signal.
@Suite("Tag")
struct NomiTagTests {
  @Test func everyToneMeetsAAOnItsFill() {
    for tone in [NomiTag.Tone.neutral, .warning, .error] {
      let ratio = NomiContrast.ratio(tone.textHex, tone.fillHex)
      #expect(ratio >= 4.5, "tone \(tone) is \(ratio):1")
    }
  }

  @Test func warningTextOnWarningTintIsAboveFourPointFive() {
    #expect(NomiContrast.ratio(NomiHex.warning, NomiHex.warningTint) >= 4.5)
  }

  /// Truncation is the default; wrapping is an explicit opt-in.
  @Test func tagTruncatesToOneLineUnlessWrapsIsSet() {
    #expect(NomiTag("90% of budget used").wrapsText == false)
    #expect(NomiTag("90% of budget used", tone: .warning, wrapsText: true).wrapsText == true)
  }

  @Test func tonesUseTheirTokens() {
    #expect(NomiTag.Tone.neutral.fillHex == NomiHex.iconTile)
    #expect(NomiTag.Tone.neutral.textHex == NomiHex.navy)
    #expect(NomiTag.Tone.warning.fillHex == NomiHex.warningTint)
    #expect(NomiTag.Tone.warning.textHex == NomiHex.warning)
    #expect(NomiTag.Tone.error.fillHex == NomiHex.errorTint)
    #expect(NomiTag.Tone.error.textHex == NomiHex.error)
  }
}
