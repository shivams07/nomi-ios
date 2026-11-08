import Foundation
import XCTest
@testable import NomiUI

/// The relative sync phrase has one implementation, `SyncStatusRow.relativeSyncPhrase`.
/// `MailAttentionLogic.lastSyncedPhrase` (the Connect mail card) forwards to it.
/// These tests pin both call sites over a 0.25 s grid from -2 days to +2 hours.
final class SyncPhraseParityTests: XCTestCase {
  /// A fixed clock, so no assertion depends on `Date()`.
  private let now = Date(timeIntervalSince1970: 1_000_000)

  /// Quarter-second steps from -2 days (-172 800 s) to +2 hours (+7 200 s).
  private let steps = 0...720_000

  private func offset(_ step: Int) -> TimeInterval {
    -172_800 + Double(step) * 0.25
  }

  func testBothCallSitesProduceTheSameStringAcrossTheGrid() {
    var disagreements: [String] = []
    for step in steps {
      let lastSync = now.addingTimeInterval(offset(step))
      let row = SyncStatusRow.relativeSyncPhrase(lastSync, now: now)
      let card = MailAttentionLogic.lastSyncedPhrase(lastSync, now: now)
      if row != card, disagreements.count < 5 {
        disagreements.append("offset \(offset(step)): \"\(row)\" vs \"\(card)\"")
      }
    }
    XCTAssertEqual(disagreements, [])
  }

  /// The rule itself, stated without the implementation: under one second is
  /// "just now" (including future instants), anything older is the formatter's
  /// phrase. Mirrors the boundary `relativeSyncPhrase` documents.
  func testEveryGridPointFollowsTheJustNowRuleOrTheFormatter() {
    for step in steps {
      let lastSync = now.addingTimeInterval(offset(step))
      let expected = now.timeIntervalSince(lastSync) >= 1
        ? NomiFormatters.relativeTime.localizedString(for: lastSync, relativeTo: now)
        : "just now"
      XCTAssertEqual(SyncStatusRow.relativeSyncPhrase(lastSync, now: now), expected, "offset \(offset(step))")
    }
  }

  /// The grid's full output, folded into one FNV-1a 64 value, equals the value
  /// the pre-change code produced (captured on macOS, en_IN formatter, under both
  /// the default zone and TZ=America/Los_Angeles). A change in the phrases shows
  /// up here even if both call sites change together.
  func testGridOutputIsUnchangedFromBeforeTheSingleImplementation() {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    func feed(_ text: String) {
      for byte in text.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x0000_0100_0000_01b3
      }
      hash ^= 0x0A
      hash = hash &* 0x0000_0100_0000_01b3
    }
    for step in steps {
      feed(SyncStatusRow.relativeSyncPhrase(now.addingTimeInterval(offset(step)), now: now))
    }
    XCTAssertEqual(hash, 0xbbcb_c12f_48b3_93bd)
  }

  /// Literal anchors for the phrases the Home row and the Connect mail card
  /// show, so a failure reads as a copy change rather than a hash mismatch.
  func testAnchorsReadTheSameAsBefore() {
    let anchors: [(TimeInterval, String)] = [
      (-172_800, "2 days ago"),
      (-3_600, "1 hr ago"),
      (-61, "1 min ago"),
      (-59, "59 sec ago"),
      (-1, "1 sec ago"),
      (-0.75, "just now"),
      (0, "just now"),
      (3_600, "just now"),
    ]
    for (delta, phrase) in anchors {
      let lastSync = now.addingTimeInterval(delta)
      XCTAssertEqual(SyncStatusRow.relativeSyncPhrase(lastSync, now: now), phrase, "offset \(delta)")
      XCTAssertEqual(MailAttentionLogic.lastSyncedPhrase(lastSync, now: now), phrase, "offset \(delta)")
    }
  }
}
