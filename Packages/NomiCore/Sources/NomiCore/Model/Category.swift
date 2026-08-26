import Foundation
import SwiftData

@Model
public final class Category {
  public var id: UUID = UUID()
  public var name: String = ""
  public var symbolName: String = "tag"
  public var paletteSlot: Int = 0
  public var isSystem: Bool = false
  public var sortIndex: Int = 0

  public init(
    id: UUID = UUID(),
    name: String = "",
    symbolName: String = "tag",
    paletteSlot: Int = 0,
    isSystem: Bool = false,
    sortIndex: Int = 0
  ) {
    self.id = id
    self.name = name
    self.symbolName = symbolName
    self.paletteSlot = paletteSlot
    self.isSystem = isSystem
    self.sortIndex = sortIndex
  }

  public static let uncategorizedID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
}
