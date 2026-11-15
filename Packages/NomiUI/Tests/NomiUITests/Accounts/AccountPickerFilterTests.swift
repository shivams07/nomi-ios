import Foundation
import XCTest

@testable import NomiUI

/// S8 step 7. The picker lists the accounts a payment can be assigned to: active ones,
/// plus the selected one even when it is archived, so an existing row's account still shows.
final class AccountPickerFilterTests: XCTestCase {
  private struct Row: AccountArchivable {
    let id: UUID
    let isArchived: Bool
  }

  func testArchivedAccountsAreLeftOutOfThePicker() {
    let active = Row(id: UUID(), isArchived: false)
    let archived = Row(id: UUID(), isArchived: true)
    let visible = AccountPickerFilter.visible([active, archived], selection: nil)
    XCTAssertEqual(visible.map(\.id), [active.id])
  }

  func testTheSelectedArchivedAccountStillShowsSoItsRowIsNotBlank() {
    let active = Row(id: UUID(), isArchived: false)
    let archived = Row(id: UUID(), isArchived: true)
    let visible = AccountPickerFilter.visible([active, archived], selection: archived.id)
    XCTAssertEqual(visible.map(\.id), [active.id, archived.id])
  }

  func testSelectingAnActiveAccountDoesNotBringBackAnArchivedOne() {
    let active = Row(id: UUID(), isArchived: false)
    let archived = Row(id: UUID(), isArchived: true)
    let visible = AccountPickerFilter.visible([active, archived], selection: active.id)
    XCTAssertEqual(visible.map(\.id), [active.id])
  }

  func testTheListKeepsItsOrder() {
    let first = Row(id: UUID(), isArchived: false)
    let archived = Row(id: UUID(), isArchived: true)
    let second = Row(id: UUID(), isArchived: false)
    let visible = AccountPickerFilter.visible([first, archived, second], selection: archived.id)
    XCTAssertEqual(visible.map(\.id), [first.id, archived.id, second.id])
  }
}
