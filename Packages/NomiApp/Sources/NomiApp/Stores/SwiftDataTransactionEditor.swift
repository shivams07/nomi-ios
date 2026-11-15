import Foundation
import NomiCore
import SwiftData

/// The real `TransactionEditing`. Constructed directly in `RootView` from
/// `environment.container.mainContext` and `environment.coordinator` rather
/// than living on `AppEnvironment` — that file belongs to
/// `park/account-binding-loop`. Fold both this construction and the protocol
/// into `AppEnvironment`/`TransactionStore` once units 1, 3 and 5a have all
/// merged (see `TransactionEditing`'s note).
@MainActor
public final class SwiftDataTransactionEditor: TransactionEditing {
  private let context: ModelContext
  private let coordinator: WriteCoordinator
  private let now: () -> Date
  /// The device calendar (DEC-05 R6): the transfer window is three calendar days
  /// in the user's own calendar, not the India calendar the dedupe key uses.
  private let calendar: Calendar

  public init(
    context: ModelContext,
    coordinator: WriteCoordinator,
    now: @escaping () -> Date = { Date() },
    calendar: Calendar = .current
  ) {
    self.context = context
    self.coordinator = coordinator
    self.now = now
    self.calendar = calendar
  }

  /// R8. A new amount outside `AmountRules` is refused before any field is read or
  /// written, so a refused edit leaves the row exactly as it was. An amount equal to
  /// the stored one is never refused: a date-only edit re-sends the stored amount, and
  /// an imported row can legitimately hold a value above the bound.
  public func update(_ id: UUID, amountMinor: Int, date: Date, descriptionText: String, note: String?) throws {
    guard let row = try row(id: id) else { return }
    if amountMinor != row.amountMinor {
      guard AmountRules.isValidTransactionAmount(amountMinor) else {
        throw AmountValidationError.outOfRange(amountMinor: amountMinor)
      }
    }
    let timestamp = now()
    let normalized = normalizeDescription(descriptionText)

    row.amountMinor = amountMinor
    row.date = date
    row.descriptionText = descriptionText
    row.normalizedDescription = normalized
    // No `calendar:` argument — this editor inherits whichever default
    // `makeDedupeKey` has when `park/dedupe-key-ist` merges, same as every
    // other call site the fix plan didn't touch.
    row.dedupeKey = makeDedupeKey(
      date: date,
      amountMinor: amountMinor,
      directionRaw: row.directionRaw,
      normalizedDescription: normalized
    )
    // U24: stored as-is, same as every other field here — `note` never
    // feeds `dedupeKey`/`normalizedDescription` (see `Transaction.note`'s
    // doc: two devices' notes on the same row must not split it in two).
    row.note = note
    row.updatedAt = timestamp

    // R8. Checked after the field writes, so the pair is judged on the new amount
    // and date. Only the categories this call touches are reported.
    var affected: Set<UUID> = Set([row.categoryID].compactMap { $0 })
    if let partner = try unpairIfNoLongerMatching(row, at: timestamp), let category = partner.categoryID {
      affected.insert(category)
    }

    try context.save()
    coordinator.didWrite(affectedCategoryIDs: affected)
  }

  /// R8. An amount or date edit can leave a transfer pair that no longer matches.
  /// Such a pair is unpaired: both legs go to `(nil, nil)`, never `rejected`. The
  /// user changed a number; they did not reject the transfer, and the detector may
  /// pair them again if they match again.
  ///
  /// Only a group of exactly two is judged. Zero, or more than two, members leave
  /// the group alone, as does a `rejected` or unrecognised pair. Returns the partner
  /// it unpaired, if any.
  private func unpairIfNoLongerMatching(_ row: Transaction, at timestamp: Date) throws -> Transaction? {
    let state = TransferRules.state(row.transferPair)
    guard state == .auto || state == .manual, let group = row.transferGroupID else { return nil }

    let target: UUID? = group
    let rowID = row.id
    let others = try context.fetch(
      FetchDescriptor<Transaction>(
        predicate: #Predicate<Transaction> { $0.transferGroupID == target && $0.id != rowID }
      ))
    guard others.count == 1, let partner = others.first else { return nil }
    guard !TransferRules.matches(row.transferLeg, partner.transferLeg, calendar: calendar) else { return nil }

    row.transferGroupID = nil
    row.transferSource = nil
    row.updatedAt = timestamp
    partner.transferGroupID = nil
    partner.transferSource = nil
    partner.updatedAt = timestamp
    return partner
  }

  /// DEC-05 R7. One write, one `WriteCoordinator` notification.
  ///
  /// Marking a row that is already a leg writes nothing. Marking otherwise finds
  /// the one free partner `TransferRules.manualPartner` accepts; with one, both
  /// legs take the pair's group id, else the row goes alone under its own
  /// `solo` id. Unmarking clears every row in the group and records `rejected`
  /// on the row touched, so the detector never marks it again.
  public func setTransfer(_ id: UUID, isTransfer: Bool) throws {
    guard let row = try row(id: id) else { return }
    let timestamp = now()
    var touched: [Transaction] = []

    if isTransfer {
      guard row.transferGroupID == nil else { return }
      if let partner = try manualPartner(for: row) {
        let group = TransferGroupID.make(row.id, partner.id)
        row.transferGroupID = group
        row.transferSource = .manual
        partner.transferGroupID = group
        partner.transferSource = .manual
        partner.updatedAt = timestamp
        touched.append(partner)
      } else {
        row.transferGroupID = TransferGroupID.make(single: row.id)
        row.transferSource = .manual
      }
    } else {
      guard row.transferGroupID != nil || row.transferSource != .rejected else { return }
      if let group = row.transferGroupID {
        let target: UUID? = group
        let members = try context.fetch(
          FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { $0.transferGroupID == target })
        )
        for member in members where member.id != row.id {
          member.transferGroupID = nil
          member.transferSource = nil
          member.updatedAt = timestamp
          touched.append(member)
        }
      }
      row.transferGroupID = nil
      row.transferSource = .rejected
    }

    row.updatedAt = timestamp
    touched.insert(row, at: 0)
    try context.save()
    coordinator.didWrite(affectedCategoryIDs: Set(touched.compactMap(\.categoryID)))
  }

  /// The candidates are the rows of the same amount within four days of the
  /// row, a window wider than the three-day rule so the start-of-day comparison
  /// in `TransferRules` never misses an edge. The rule itself decides.
  private func manualPartner(for row: Transaction) throws -> Transaction? {
    guard row.currencyCode == "INR", row.accountID != nil else { return nil }
    guard
      let lower = calendar.date(byAdding: .day, value: -4, to: row.date),
      let upper = calendar.date(byAdding: .day, value: 4, to: row.date)
    else { return nil }
    let amount = row.amountMinor
    let descriptor = FetchDescriptor<Transaction>(
      predicate: #Predicate<Transaction> {
        $0.amountMinor == amount && $0.date >= lower && $0.date <= upper
      }
    )
    let candidates = try context.fetch(descriptor).filter { $0.id != row.id }
    guard
      let partnerID = TransferRules.manualPartner(
        for: row.transferLeg,
        among: candidates.map(\.transferLeg),
        calendar: calendar
      )
    else { return nil }
    return candidates.first { $0.id == partnerID }
  }

  private func row(id: UUID) throws -> Transaction? {
    var descriptor = FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { $0.id == id })
    descriptor.fetchLimit = 1
    return try context.fetch(descriptor).first
  }
}
