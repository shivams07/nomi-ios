import Foundation
import NomiCore

public enum MergeTier: Sendable, Equatable {
  /// Same `dedupeKey`.
  case exact
  /// Same amount and direction, date within +/-2 days, description similarity
  /// at or above the threshold. Always sets `needsReview`.
  case near
}

/// The two-tier merge search. Pure.
enum DedupeMatcher {
  static let nearDayWindow = 2
  static let nearSimilarityThreshold = 0.9

  /// The date span a candidate fetch must cover to find both tiers.
  static func candidateDateRange(for date: Date, calendar: Calendar) -> ClosedRange<Date> {
    let start = calendar.startOfDay(for: date)
    let lower = calendar.date(byAdding: .day, value: -nearDayWindow, to: start) ?? start
    let dayAfterUpper = calendar.date(byAdding: .day, value: nearDayWindow + 1, to: start) ?? start
    return lower...dayAfterUpper
  }

  static func match(
    _ derived: DerivedDraft,
    in candidates: [TransactionSnapshot],
    calendar: Calendar
  ) -> (row: TransactionSnapshot, tier: MergeTier)? {
    if let exact = exactMatch(derived, in: candidates) {
      return (exact, .exact)
    }
    if let near = nearMatch(derived, in: candidates, calendar: calendar) {
      return (near, .near)
    }
    return nil
  }

  static func exactMatch(
    _ derived: DerivedDraft,
    in candidates: [TransactionSnapshot]
  ) -> TransactionSnapshot? {
    candidates
      .filter { $0.dedupeKey == derived.dedupeKey }
      .min { lhs, rhs in
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
      }
  }

  static func nearMatch(
    _ derived: DerivedDraft,
    in candidates: [TransactionSnapshot],
    calendar: Calendar
  ) -> TransactionSnapshot? {
    let draft = derived.draft
    let draftDay = calendar.startOfDay(for: draft.date)

    let scored: [(row: TransactionSnapshot, dayDelta: Int, similarity: Double)] =
      candidates.compactMap { row in
        guard row.dedupeKey != derived.dedupeKey else { return nil }
        guard row.amountMinor == draft.amountMinor else { return nil }
        guard row.directionRaw == draft.direction.rawValue else { return nil }

        let rowDay = calendar.startOfDay(for: row.date)
        guard let days = calendar.dateComponents([.day], from: draftDay, to: rowDay).day else {
          return nil
        }
        let delta = abs(days)
        guard delta <= nearDayWindow else { return nil }

        let similarity = Similarity.ratio(row.normalizedDescription, derived.normalizedDescription)
        guard similarity >= nearSimilarityThreshold else { return nil }

        return (row, delta, similarity)
      }

    return scored.min { lhs, rhs in
      if lhs.dayDelta != rhs.dayDelta { return lhs.dayDelta < rhs.dayDelta }
      if lhs.similarity != rhs.similarity { return lhs.similarity > rhs.similarity }
      if lhs.row.createdAt != rhs.row.createdAt { return lhs.row.createdAt < rhs.row.createdAt }
      return lhs.row.id.uuidString < rhs.row.id.uuidString
    }?.row
  }
}
