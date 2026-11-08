import CryptoKit
import Foundation

/// The deterministic id of a transfer group (DEC-05).
///
/// Two devices that mark the same pair write the same value without talking to
/// each other, which is what makes the id safe under CloudKit. Exclusion never
/// depends on this value matching the partner's: a row is excluded by its own
/// `transferGroupID`, so a sync conflict that leaves two legs with different ids
/// still excludes both.
public enum TransferGroupID {
  /// The group of two rows. Order-independent: `make(a, b) == make(b, a)`.
  ///
  /// Over the two lowercase UUID strings, sorted and joined with `|`, first 16
  /// bytes of SHA-256.
  public static func make(_ a: UUID, _ b: UUID) -> UUID {
    let parts = [a, b].map { $0.uuidString.lowercased() }.sorted()
    return digest("\(parts[0])|\(parts[1])")
  }

  /// The group of a single row marked alone. Over `solo|` plus its lowercase
  /// UUID, so it differs from every pair form.
  public static func make(single id: UUID) -> UUID {
    digest("solo|" + id.uuidString.lowercased())
  }

  private static func digest(_ text: String) -> UUID {
    let hash = Array(SHA256.hash(data: Data(text.utf8)).prefix(16))
    return UUID(uuid: (
      hash[0], hash[1], hash[2], hash[3], hash[4], hash[5], hash[6], hash[7],
      hash[8], hash[9], hash[10], hash[11], hash[12], hash[13], hash[14], hash[15]
    ))
  }
}
