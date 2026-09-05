import Foundation
import SwiftData

/// What kind of thing an `Account` is.
///
/// `Account.kindRaw` stays a `String` because that is what the stored column
/// is and changing a `@Model`'s property type is a migration; this is the
/// raw-backed accessor over it, exactly as `Transaction.direction` is over
/// `directionRaw`.
///
/// No `.cash` case. A cash wallet is not a fourth label on the same concept -
/// it needs a transfer concept and a balance the app maintains, which is a
/// schema decision (M5) and not one to make inside this PR.
public enum AccountKind: String, Codable, CaseIterable, Sendable {
  case bank, card, wallet
}

/// Rejections from `AccountStore.create`.
///
/// These used to be preconditions the caller held and nothing checked. The
/// caller was one SwiftUI form, so "the only caller cannot produce that state"
/// was true right up until a second caller existed - and the App Intent in
/// U23 is that second caller.
public enum AccountStoreError: Error, Sendable, Equatable {
  case blankName
  /// `lastFour` must be exactly four digits, or empty. Never partial: it is
  /// the `cardFragment` half of the `AccountBinding` key, so "471" or
  /// "•• 4471" would silently stop mail auto-resolution ever matching, with
  /// no visible symptom anywhere.
  case malformedLastFour
  case unknownKind(String)
}

@Model
public final class Account {
  public var id: UUID = UUID()
  public var displayName: String = ""
  public var institution: String = ""
  public var lastFour: String = ""
  public var kindRaw: String = "bank"
  public var isArchived: Bool = false
  public var createdAt: Date = Date()

  public init(
    id: UUID = UUID(),
    displayName: String = "",
    institution: String = "",
    lastFour: String = "",
    kindRaw: String = "bank",
    isArchived: Bool = false,
    createdAt: Date = Date()
  ) {
    self.id = id
    self.displayName = displayName
    self.institution = institution
    self.lastFour = lastFour
    self.kindRaw = kindRaw
    self.isArchived = isArchived
    self.createdAt = createdAt
  }

  /// Raw-backed, like `Transaction.direction`. The getter falls back to
  /// `.bank` for a value it does not recognise rather than trapping - a row
  /// synced from a future version of the app must render, not crash. Writes
  /// go through the enum, so nothing this app stores can be unrecognised.
  public var kind: AccountKind {
    get { AccountKind(rawValue: kindRaw) ?? .bank }
    set { kindRaw = newValue.rawValue }
  }
}

@Model
public final class AccountBinding {
  public var id: UUID = UUID()
  public var senderDomain: String = ""
  public var cardFragment: String = ""
  public var accountID: UUID = UUID()

  public init(
    id: UUID = UUID(),
    senderDomain: String = "",
    cardFragment: String = "",
    accountID: UUID = UUID()
  ) {
    self.id = id
    self.senderDomain = senderDomain
    self.cardFragment = cardFragment
    self.accountID = accountID
  }
}

@Model
public final class ColumnMappingRecord {
  public var id: UUID = UUID()
  public var formatSignature: String = ""
  public var bankLabel: String = ""
  public var mappingJSON: String = ""

  public init(
    id: UUID = UUID(),
    formatSignature: String = "",
    bankLabel: String = "",
    mappingJSON: String = ""
  ) {
    self.id = id
    self.formatSignature = formatSignature
    self.bankLabel = bankLabel
    self.mappingJSON = mappingJSON
  }
}
