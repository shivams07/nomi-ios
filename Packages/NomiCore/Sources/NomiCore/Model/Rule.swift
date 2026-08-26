import Foundation
import SwiftData

@Model
public final class Rule {
  public var id: UUID = UUID()
  public var pattern: String = ""
  public var categoryID: UUID = UUID()
  public var priority: Int = 0
  public var isEnabled: Bool = true
  public var createdAt: Date = Date()

  public init(
    id: UUID = UUID(),
    pattern: String = "",
    categoryID: UUID = UUID(),
    priority: Int = 0,
    isEnabled: Bool = true,
    createdAt: Date = Date()
  ) {
    self.id = id
    self.pattern = pattern
    self.categoryID = categoryID
    self.priority = priority
    self.isEnabled = isEnabled
    self.createdAt = createdAt
  }
}
