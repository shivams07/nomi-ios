import Foundation
import SwiftData

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
