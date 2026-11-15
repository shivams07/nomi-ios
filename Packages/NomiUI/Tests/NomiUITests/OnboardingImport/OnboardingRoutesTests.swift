import XCTest

@testable import NomiUI

final class OnboardingRoutesTests: XCTestCase {

  /// The SMS route (A1 and A2) is not shipped, so its card and its Continue
  /// title stay hidden in this build.
  func testSmsIsNotAvailableInThisBuild() {
    XCTAssertFalse(OnboardingRoutes.smsAvailable)
  }

  func testEmailAloneContinuesWithEmail() {
    XCTAssertEqual(OnboardingRoutes.continueTitle(smsOn: false, emailOn: true), "Continue with email")
  }

  /// While SMS is unavailable, a selected SMS card cannot change the title.
  func testSmsSelectionDoesNotChangeTheTitleWhileUnavailable() {
    XCTAssertEqual(OnboardingRoutes.continueTitle(smsOn: true, emailOn: true), "Continue with email")
  }

  func testBothRoutesReadAsSmsAndEmailWhenSmsIsAvailable() {
    XCTAssertEqual(
      OnboardingRoutes.continueTitle(smsOn: true, emailOn: true, smsAvailable: true),
      "Continue with SMS and email")
  }

  /// The email note names only the providers the app offers on the connect
  /// step (MailProvider), not the canvas's Yahoo, which the app has no provider for.
  func testEmailNoteNamesOnlyTheProvidersTheAppSupports() {
    let note = OnboardingRoutes.emailRouteNote()
    for provider in MailProvider.allCases {
      XCTAssertTrue(note.contains(provider.displayName), "missing \(provider.displayName) in \(note)")
    }
    XCTAssertFalse(note.contains("Yahoo"))
    XCTAssertTrue(note.hasSuffix("Nomi keeps only the amount, merchant and date."))
  }

  func testProviderListJoinsWithCommasAndAnd() {
    XCTAssertEqual(
      OnboardingRoutes.providerList([.gmail, .icloud, .zoho]),
      "Gmail, iCloud Mail and Zoho Mail")
  }

  func testProviderListOfOneNameHasNoJoin() {
    XCTAssertEqual(OnboardingRoutes.providerList([.gmail]), "Gmail")
  }

  /// No automatic route selected: the pill is disabled, so there is no title.
  func testNoRouteSelectedHasNoContinueTitle() {
    XCTAssertNil(OnboardingRoutes.continueTitle(smsOn: false, emailOn: false))
  }

  /// The SMS route has no screen in this unit, so SMS alone has nowhere to go
  /// and no title, even when SMS is available.
  func testSmsAloneHasNoContinueTitleBecauseItsRouteIsNotBuilt() {
    XCTAssertNil(OnboardingRoutes.continueTitle(smsOn: true, emailOn: false, smsAvailable: true))
    XCTAssertNil(OnboardingRoutes.continueTitle(smsOn: true, emailOn: false))
  }
}
