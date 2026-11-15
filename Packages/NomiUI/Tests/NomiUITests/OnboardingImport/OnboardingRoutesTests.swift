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
      XCTAssertTrue(
        note.contains(OnboardingRoutes.providerName(provider)),
        "missing \(provider) in \(note)")
    }
    XCTAssertFalse(note.contains("Yahoo"))
    XCTAssertFalse(note.contains("Generic IMAP"), "user wording, not the enum's display name")
    XCTAssertTrue(
      note.hasSuffix(
        "Nomi reads only bank-like senders and keeps each transaction's amount, date and a short description of the alert, not the whole email."),
      note)
  }

  func testProviderListJoinsWithCommasAndAnd() {
    XCTAssertEqual(
      OnboardingRoutes.providerList([.gmail, .icloud, .zoho]),
      "Gmail, iCloud Mail and Zoho Mail")
  }

  /// The generic case is worded as the user would say it.
  func testGenericProviderIsWordedAsOtherIMAPMail() {
    XCTAssertEqual(OnboardingRoutes.providerName(.generic), "other IMAP mail")
    XCTAssertEqual(
      OnboardingRoutes.providerList([.gmail, .generic]),
      "Gmail and other IMAP mail")
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
