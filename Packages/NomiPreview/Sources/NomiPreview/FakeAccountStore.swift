import Foundation
import NomiCore

@MainActor
public final class FakeAccountStore: AccountStore {
  public var accounts: [Account]

  public init(accounts: [Account] = PreviewData.accounts) {
    self.accounts = accounts
  }

  /// Appends, and returns the same instance it appended.
  ///
  /// Both halves matter. `FakeInsightsStore` is constructed from an `[Account]`
  /// and derives its summaries from it, so a fake that created an account
  /// somewhere else would give the previews an Accounts screen where the new
  /// row never appears — demonstrating, on every preview and in every UI test
  /// built on this store, the exact failure the real store's `didWrite` exists
  /// to prevent. Returning the appended instance rather than a copy is what
  /// lets a caller hand `accounts` straight to `FakeInsightsStore` afterwards.
  @discardableResult
  public func create(
    displayName: String,
    institution: String,
    lastFour: String,
    kindRaw: String
  ) throws -> Account {
    let account = Account(
      displayName: displayName,
      institution: institution,
      lastFour: lastFour,
      kindRaw: kindRaw
    )
    accounts.append(account)
    return account
  }

  public func rename(_ id: UUID, to displayName: String) throws {
    guard let account = accounts.first(where: { $0.id == id }) else { return }
    account.displayName = displayName
  }

  public func setArchived(_ id: UUID, _ archived: Bool) throws {
    guard let account = accounts.first(where: { $0.id == id }) else { return }
    account.isArchived = archived
  }
}
