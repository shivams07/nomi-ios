import Foundation
import XCTest

@testable import NomiUI

/// `AboutLogic` (S9b). The version line is read from a stub Info dictionary
/// bundle written to a temporary folder; nothing here renders a view.
final class AboutLogicTests: XCTestCase {
  private var stubFolders: [URL] = []

  override func tearDown() {
    for folder in stubFolders {
      try? FileManager.default.removeItem(at: folder)
    }
    stubFolders = []
    super.tearDown()
  }

  /// A bundle whose Info.plist holds `info`, so `Bundle.infoDictionary` returns it.
  private func stubBundle(info: [String: Any]) throws -> Bundle {
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("AboutStub-\(UUID().uuidString).bundle", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    stubFolders.append(folder)
    let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try data.write(to: folder.appendingPathComponent("Info.plist"))
    return try XCTUnwrap(Bundle(url: folder))
  }

  // MARK: - Version line

  func testVersionLineReadsShortVersionAndBuild() throws {
    let bundle = try stubBundle(info: ["CFBundleShortVersionString": "1.0", "CFBundleVersion": "1"])
    XCTAssertEqual(AboutLogic.versionLine(bundle: bundle), "Version 1.0 (1)")
  }

  func testVersionLineFallsBackToModuleVersionWhenKeysAreAbsent() throws {
    let bundle = try stubBundle(info: [:])
    XCTAssertEqual(AboutLogic.versionLine(bundle: bundle), "Version \(NomiUIModule.version)")
  }

  func testVersionLineFallsBackWhenBuildIsMissing() throws {
    let bundle = try stubBundle(info: ["CFBundleShortVersionString": "1.0"])
    XCTAssertEqual(AboutLogic.versionLine(bundle: bundle), "Version \(NomiUIModule.version)")
  }

  // MARK: - Legal rows

  func testLegalRowsAreHiddenWhileTheirURLsAreNil() {
    XCTAssertEqual(AboutLogic.visibleRows(privacy: nil, terms: nil), [.support, .licences])
  }

  func testLegalRowsAppearOnceTheirURLsAreSet() {
    let privacy = URL(string: "https://example.com/privacy")
    let terms = URL(string: "https://example.com/terms")
    XCTAssertEqual(
      AboutLogic.visibleRows(privacy: privacy, terms: terms),
      [.privacyPolicy, .termsOfUse, .support, .licences]
    )
  }

  func testEachLegalRowIsShownOnlyForItsOwnURL() {
    let privacy = URL(string: "https://example.com/privacy")
    XCTAssertEqual(AboutLogic.visibleRows(privacy: privacy, terms: nil), [.privacyPolicy, .support, .licences])
    XCTAssertEqual(AboutLogic.visibleRows(privacy: nil, terms: privacy), [.termsOfUse, .support, .licences])
  }

  // MARK: - Footer and support address

  func testFooterIsHiddenWithoutAPublisherName() {
    XCTAssertNil(AboutLogic.footer(publisherName: nil, year: 2026))
    XCTAssertNil(AboutLogic.footer(publisherName: "   ", year: 2026))
  }

  func testFooterNamesTheYearAndPublisher() {
    XCTAssertEqual(AboutLogic.footer(publisherName: "Test Publisher", year: 2026), "© 2026 Test Publisher")
  }

  func testSupportAddressBecomesAMailtoURL() {
    XCTAssertEqual(
      AboutLogic.mailtoURL(address: LegalLinks.supportEmail)?.absoluteString,
      "mailto:\(LegalLinks.supportEmail)"
    )
  }

  // MARK: - Licences

  func testBundledLicencesNameSwiftNIOAndInter() throws {
    let text = try XCTUnwrap(AboutLogic.licencesText())
    XCTAssertFalse(text.isEmpty)
    XCTAssertTrue(text.contains("swift-nio"))
    XCTAssertTrue(text.contains("SIL Open Font License"))
  }
}
