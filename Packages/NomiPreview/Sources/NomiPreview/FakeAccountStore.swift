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

  /// Validates, like the real store. A preview of the edit sheet whose Save
  /// always succeeds would not show the error state the sheet exists to have.
  /// The five-argument create with an opening balance, validated the way the real store validates it:
  /// the same rules as `update`, and nothing appended when one fails.
  @discardableResult
  public func create(
    displayName: String,
    institution: String,
    lastFour: String,
    kindRaw: String,
    openingBalanceMinor: Int?
  ) throws -> Account {
    let trimmedName = try Self.validated(
      displayName: displayName, lastFour: lastFour, kindRaw: kindRaw,
      openingBalanceMinor: openingBalanceMinor)
    let account = Account(
      displayName: trimmedName,
      institution: institution,
      lastFour: lastFour,
      kindRaw: kindRaw,
      openingBalanceMinor: openingBalanceMinor
    )
    accounts.append(account)
    return account
  }

  public func update(
    _ id: UUID,
    displayName: String,
    institution: String,
    lastFour: String,
    kindRaw: String,
    openingBalanceMinor: Int?
  ) throws {
    // R8b: an opening balance outside AmountRules is refused before the lookup, as the
    // real store refuses it.
    let trimmedName = try Self.validated(
      displayName: displayName, lastFour: lastFour, kindRaw: kindRaw,
      openingBalanceMinor: openingBalanceMinor)

    guard let account = accounts.first(where: { $0.id == id }) else { return }
    account.displayName = trimmedName
    account.institution = institution
    account.lastFour = lastFour
    account.kindRaw = kindRaw
    account.openingBalanceMinor = openingBalanceMinor
  }

  /// Drops the account from `accounts`, which is all this fake can do: it
  /// holds no transactions and no bindings, so the half of the real `delete`
  /// that matters most — rows kept with a nil `accountID` — has nothing to act
  /// on here and is pinned against a real container in `AccountStoreTests`
  /// instead.
  public func delete(_ id: UUID) throws {
    accounts.removeAll { $0.id == id }
  }

  /// The rules `create` and `update` both enforce, in the real store's order: name, `lastFour`, kind,
  /// then the opening balance. Returns the trimmed name.
  private static func validated(
    displayName: String,
    lastFour: String,
    kindRaw: String,
    openingBalanceMinor: Int?
  ) throws -> String {
    let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else { throw AccountStoreError.blankName }
    guard lastFour.isEmpty
      || (lastFour.count == 4 && lastFour.allSatisfy { $0.isASCII && $0.isNumber })
    else { throw AccountStoreError.malformedLastFour }
    guard AccountKind(rawValue: kindRaw) != nil else {
      throw AccountStoreError.unknownKind(kindRaw)
    }
    if let opening = openingBalanceMinor, !AmountRules.isValidOpeningBalance(opening) {
      throw AmountValidationError.outOfRange(amountMinor: opening)
    }
    return trimmedName
  }
}
