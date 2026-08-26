import Foundation
import SwiftData

@Model
public final class Budget {
  public var id: UUID = UUID()
  public var categoryID: UUID = UUID()
  public var amountMinor: Int = 0
  public var isEnabled: Bool = true
  public var createdAt: Date = Date()

  public init(
    id: UUID = UUID(),
    categoryID: UUID = UUID(),
    amountMinor: Int = 0,
    isEnabled: Bool = true,
    createdAt: Date = Date()
  ) {
    self.id = id
    self.categoryID = categoryID
    self.amountMinor = amountMinor
    self.isEnabled = isEnabled
    self.createdAt = createdAt
  }
}

@Model
public final class BudgetAlertLog {
  public var id: UUID = UUID()
  public var categoryID: UUID = UUID()
  public var periodKey: String = ""
  public var firedAt: Date = Date()
  public var wasSuppressed: Bool = false

  public init(
    id: UUID = UUID(),
    categoryID: UUID = UUID(),
    periodKey: String = "",
    firedAt: Date = Date(),
    wasSuppressed: Bool = false
  ) {
    self.id = id
    self.categoryID = categoryID
    self.periodKey = periodKey
    self.firedAt = firedAt
    self.wasSuppressed = wasSuppressed
  }
}
