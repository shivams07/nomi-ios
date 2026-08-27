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
  public func top(_ limit: Int = 10) -> [UnmatchedSender] {
    counts
      .map { UnmatchedSender(domain: $0.key, count: $0.value) }
      .sorted {
        $0.count == $1.count ? $0.domain < $1.domain : $0.count > $1.count
      }
      .prefix(limit)
      .map { $0 }
  }

  public var isEmpty: Bool { counts.isEmpty }
}
