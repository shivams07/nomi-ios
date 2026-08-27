import Foundation
import NomiCore

/// Counts the sender **domains** that fell through to Layer 2.
///
/// This is the field that replaced the question nobody was willing to ask
/// (§2.5.1). The app produces the real bank list on the user's own device at
/// first backfill; no agent reads a mailbox, and no one is asked which banks
/// they use.
///
/// **Domain only. Never a full address, never a subject line.** The type below
/// physically cannot carry either — `record` takes a `MailMessage` and keeps
/// `senderDomain`, so there is no code path where an address reaches a
/// `SyncSummary`.
public struct UnmatchedSenderTally: Sendable, Equatable {
  private var counts: [String: Int] = [:]

  public init() {}

  public mutating func record(_ message: MailMessage) {
    let domain = message.senderDomain
    guard !domain.isEmpty else { return }
    counts[domain, default: 0] += 1
  }

  /// Folds another tally's counts in.
  ///
  /// A backfill classifies one batch at a time (§2.17), so the run's tally is
  /// the sum of ~60 of these. It has to merge at the **counts**, not at `top()`:
  /// a domain sitting eleventh in every batch and first overall would never
  /// appear if the batches were reduced through their own top-10 lists first.
  public mutating func merge(_ other: UnmatchedSenderTally) {
    for (domain, count) in other.counts {
      counts[domain, default: 0] += count
    }
  }

  /// Descending by count, max 10 (§2.5.1). Ties broken alphabetically so two
  /// syncs over the same mail report the same order — a report that reshuffles
  /// on every run is a report nobody trusts.
  ///
  /// Written as statements rather than a `map`/`sorted`/`prefix`/`map` chain:
  /// as one expression, with the comparator an inline ternary over a dictionary
  /// element's `$0.key`/`$0.value`, the type-checker gives up
  /// (*"unable to type-check this expression in reasonable time"*). The array
  /// is annotated and the comparator is a named function with concrete
  /// parameter types, so nothing here is left for inference to reconstruct.
  public func top(_ limit: Int = 10) -> [UnmatchedSender] {
    var senders: [UnmatchedSender] = []
    senders.reserveCapacity(counts.count)
    for (domain, count) in counts {
      senders.append(UnmatchedSender(domain: domain, count: count))
    }
    senders.sort(by: Self.rankedBefore)
    return Array(senders.prefix(limit))
  }

  /// Descending by count, ties alphabetical by domain.
  private static func rankedBefore(_ a: UnmatchedSender, _ b: UnmatchedSender) -> Bool {
    if a.count != b.count { return a.count > b.count }
    return a.domain < b.domain
  }

  public var isEmpty: Bool { counts.isEmpty }
}
