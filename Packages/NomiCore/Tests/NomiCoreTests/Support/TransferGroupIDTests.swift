import Foundation
import Testing

@testable import NomiCore

/// DEC-05 A-05 item 9. The group id is what two devices must agree on without
/// talking, so these pin its shape, not just its self-consistency.
struct TransferGroupIDTests {
  private let a = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
  private let b = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

  @Test func pairIdIsOrderIndependent() {
    #expect(TransferGroupID.make(a, b) == TransferGroupID.make(b, a))
  }

  @Test func singleIdDiffersFromEveryPairForm() {
    #expect(TransferGroupID.make(single: a) != TransferGroupID.make(a, b))
    #expect(TransferGroupID.make(single: a) != TransferGroupID.make(a, a))
    #expect(TransferGroupID.make(single: b) != TransferGroupID.make(a, b))
  }

  @Test func singleIdIsStableForTheSameRow() {
    #expect(TransferGroupID.make(single: a) == TransferGroupID.make(single: a))
  }

  /// Known answers, computed outside the code: the first 16 bytes of SHA-256
  /// over `11111111-2222-3333-4444-555555555555|aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee`
  /// (lowercase, sorted, `|`), and over `solo|11111111-2222-3333-4444-555555555555`.
  @Test func pairAndSingleMatchKnownVectors() {
    #expect(
      TransferGroupID.make(a, b)
        == UUID(uuidString: "e7bbc2de-76d8-1508-e730-2faaaa12f207"))
    #expect(
      TransferGroupID.make(single: a)
        == UUID(uuidString: "3c85b4b6-d48c-3bfd-35ce-b8c9a0fd2393"))
  }
}
