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
      isOnScreen: false, heroMinY: 0, heroMaxY: 356, overlap: 24, safeTop: 54)
    #expect(tone == nil)
  }

  @Test("Home at rest, with the hero under the status bar, is light")
  func heroAtRestIsLight() {
    let tone = NomiStatusBarToneRule.tone(
      isOnScreen: true, heroMinY: 0, heroMaxY: 356, overlap: 24, safeTop: 54)
    #expect(tone == .light)
  }

  @Test("Accounts at rest, with the shorter hero under the status bar, is light")
  func accountsAtRestIsLight() {
    let tone = NomiStatusBarToneRule.tone(
      isOnScreen: true, heroMinY: 0, heroMaxY: 250, overlap: 24, safeTop: 54)
    #expect(tone == .light)
  }

  @Test("a hero scrolled past the status bar is dark")
  func scrolledPastIsDark() {
    let tone = NomiStatusBarToneRule.tone(
      isOnScreen: true, heroMinY: -340, heroMaxY: 16, overlap: 24, safeTop: 54)
    #expect(tone == .dark)
  }

  @Test("the midpoint boundary is inclusive: the visible hero bottom at 27 is light")
  func boundaryInclusive() {
    let tone = NomiStatusBarToneRule.tone(
      isOnScreen: true, heroMinY: -300, heroMaxY: 51, overlap: 24, safeTop: 54)
    #expect(tone == .light)
  }

  @Test("one point below the midpoint boundary is dark")
  func boundaryOneBelow() {
    let tone = NomiStatusBarToneRule.tone(
      isOnScreen: true, heroMinY: -300, heroMaxY: 50.9, overlap: 24, safeTop: 54)
    #expect(tone == .dark)
  }

  @Test("pull-down overscroll that exposes ground above the hero is dark")
  func pullDownGapIsDark() {
    let tone = NomiStatusBarToneRule.tone(
      isOnScreen: true, heroMinY: 28, heroMaxY: 384, overlap: 24, safeTop: 54)
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
}
