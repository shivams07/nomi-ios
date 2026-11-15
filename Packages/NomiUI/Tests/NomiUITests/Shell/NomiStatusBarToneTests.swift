import SwiftUI
import Testing
@testable import NomiUI

// clt-harness: include

/// SB1's pure rules: when the hero is off screen the tone is nil, the midpoint
/// test for the hero under the status bar (with its inclusive boundary), the
/// reduction that lets light win, and the one question NomiApp asks. Swift-testing,
/// so the CLT harness runs them too.
///
/// Numbers are at a 54 pt safe-area top (midpoint 27) and a 24 pt sheet overlap,
/// the Home (sheet top 332) and Accounts (sheet top 226) artboard values.
@Suite("Status bar tone")
struct NomiStatusBarToneTests {
  @Test("a hero that is not on screen reports no tone")
  func offScreenIsNil() {
    let tone = NomiStatusBarToneRule.tone(
      isOnScreen: false, heroMinY: 0, heroMaxY: 356, overlap: 24, safeTop: 54, whiteLimitY: NomiHeroGradient.whiteTextFloor)
    #expect(tone == nil)
  }

  @Test("Home at rest, with the hero under the status bar, is light")
  func heroAtRestIsLight() {
    let tone = NomiStatusBarToneRule.tone(
      isOnScreen: true, heroMinY: 0, heroMaxY: 356, overlap: 24, safeTop: 54, whiteLimitY: NomiHeroGradient.whiteTextFloor)
    #expect(tone == .light)
  }

  @Test("Accounts at rest, with the shorter hero under the status bar, is light")
  func accountsAtRestIsLight() {
    let tone = NomiStatusBarToneRule.tone(
      isOnScreen: true, heroMinY: 0, heroMaxY: 250, overlap: 24, safeTop: 54, whiteLimitY: NomiHeroGradient.whiteTextFloor)
    #expect(tone == .light)
  }

  @Test("a hero scrolled past the status bar is dark")
  func scrolledPastIsDark() {
    let tone = NomiStatusBarToneRule.tone(
      isOnScreen: true, heroMinY: -340, heroMaxY: 16, overlap: 24, safeTop: 54, whiteLimitY: NomiHeroGradient.whiteTextFloor)
    #expect(tone == .dark)
  }

  @Test("the midpoint boundary is inclusive: the visible hero bottom at 27 is light")
  func boundaryInclusive() {
    let tone = NomiStatusBarToneRule.tone(
      isOnScreen: true, heroMinY: -200, heroMaxY: 51, overlap: 24, safeTop: 54, whiteLimitY: NomiHeroGradient.whiteTextFloor)
    #expect(tone == .light)
  }

  @Test("one point below the midpoint boundary is dark")
  func boundaryOneBelow() {
    let tone = NomiStatusBarToneRule.tone(
      isOnScreen: true, heroMinY: -200, heroMaxY: 50.9, overlap: 24, safeTop: 54, whiteLimitY: NomiHeroGradient.whiteTextFloor)
    #expect(tone == .dark)
  }

  @Test("pull-down overscroll that exposes ground above the hero is dark")
  func pullDownGapIsDark() {
    let tone = NomiStatusBarToneRule.tone(
      isOnScreen: true, heroMinY: 28, heroMaxY: 384, overlap: 24, safeTop: 54, whiteLimitY: NomiHeroGradient.whiteTextFloor)
    #expect(tone == .dark)
  }

  @Test("light wins over dark and over nil in the reduction")
  func combineLightWins() {
    #expect(NomiStatusBarToneRule.combine(.dark, .light) == .light)
    #expect(NomiStatusBarToneRule.combine(.light, nil) == .light)
  }

  @Test("with no light side, the first non-nil tone is kept")
  func combineFirstNonNil() {
    #expect(NomiStatusBarToneRule.combine(nil, .dark) == .dark)
    #expect(NomiStatusBarToneRule.combine(nil, nil) == nil)
  }

  @Test("only a light tone asks for the light overlay")
  func overlayOnlyForLight() {
    #expect(NomiStatusBarToneRule.showsLightOverlay(.light))
    #expect(!NomiStatusBarToneRule.showsLightOverlay(.dark))
    #expect(!NomiStatusBarToneRule.showsLightOverlay(nil))
  }

  // MARK: - D5: the white-text limit (Moss floor, I-9)

  /// The gradient tail sits under the status bar's midpoint, but white text
  /// stops passing 4.5:1 below the floor, so the bar goes dark there.
  @Test("a gradient tail that is under the status bar at the floor's limit is dark")
  func darkOnceGradientTailIsUnderBand() {
    let tone = NomiStatusBarToneRule.tone(
      isOnScreen: true, heroMinY: -300, heroMaxY: 56, overlap: 24, safeTop: 62,
      whiteLimitY: NomiHeroGradient.whiteTextFloor + (62 - NomiHeroGradient.artboardSafeTop))
    #expect(tone == .dark)
  }

  @Test("a hero at rest under the status bar stays light with the floor in place")
  func lightAtRest() {
    let tone = NomiStatusBarToneRule.tone(
      isOnScreen: true, heroMinY: 0, heroMaxY: 356, overlap: 24, safeTop: 62,
      whiteLimitY: NomiHeroGradient.whiteTextFloor + (62 - NomiHeroGradient.artboardSafeTop))
    #expect(tone == .light)
  }

  @Test("the floor is inclusive: the midpoint exactly at the limit is light")
  func lightAtFloor() {
    let limit = NomiHeroGradient.whiteTextFloor + (62 - NomiHeroGradient.artboardSafeTop)
    let tone = NomiStatusBarToneRule.tone(
      isOnScreen: true, heroMinY: 31 - (299 + 8), heroMaxY: 356, overlap: 24, safeTop: 62,
      whiteLimitY: limit)
    #expect(tone == .light)
  }

  @Test("one point past the floor is dark")
  func darkOnePastFloor() {
    let limit = NomiHeroGradient.whiteTextFloor + (62 - NomiHeroGradient.artboardSafeTop)
    let tone = NomiStatusBarToneRule.tone(
      isOnScreen: true, heroMinY: 31 - (299 + 8) - 1, heroMaxY: 356, overlap: 24, safeTop: 62,
      whiteLimitY: limit)
    #expect(tone == .dark)
  }
}
