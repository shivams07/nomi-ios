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

  /// When this row was first written.
  ///
  /// Optional with no default, and no schema version bump: CloudKit accepts an
  /// added optional, and every category already on a device reads `nil`, which
  /// is the truth — nobody recorded it. `DefaultCategorySeed.apply` stamps on
  /// insert; `ReferenceDataReconciler` stamps the rest and keeps the earliest
  /// row of a duplicated id.
  public var createdAt: Date?

  public init(
    id: UUID = UUID(),
    name: String = "",
    symbolName: String = "tag",
    paletteSlot: Int = 0,
    isSystem: Bool = false,
    sortIndex: Int = 0,
    createdAt: Date? = nil
  ) {
    self.id = id
    self.name = name
    self.symbolName = symbolName
    self.paletteSlot = paletteSlot
    self.isSystem = isSystem
    self.sortIndex = sortIndex
    self.createdAt = createdAt
  }

  public static let uncategorizedID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
}
