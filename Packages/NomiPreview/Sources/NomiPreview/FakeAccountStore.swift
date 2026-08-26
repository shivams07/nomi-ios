import Foundation
import NomiCore

@MainActor
public final class FakeAccountStore: AccountStore {
  public var accounts: [Account]

  public init(accounts: [Account] = PreviewData.accounts) {
    self.accounts = accounts
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
