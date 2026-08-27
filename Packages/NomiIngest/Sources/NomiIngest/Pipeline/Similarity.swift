import Foundation

/// Normalized-description similarity for the near-match dedupe tier.
///
/// Levenshtein ratio: deterministic, no locale input, no tokenisation rules to
/// drift. It feeds merge behaviour only — never `dedupeKey` — so unlike the
/// UPI parser (§2.4) a future change here cannot orphan historical rows.
enum Similarity {
  static func ratio(_ lhs: String, _ rhs: String) -> Double {
    if lhs == rhs { return 1.0 }
    if lhs.isEmpty || rhs.isEmpty { return 0.0 }

    let a = Array(lhs)
    let b = Array(rhs)
    let distance = levenshtein(a, b)
    return 1.0 - Double(distance) / Double(max(a.count, b.count))
  }

  private static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
    var previous = Array(0...b.count)
    var current = [Int](repeating: 0, count: b.count + 1)

    for i in 1...a.count {
      current[0] = i
      for j in 1...b.count {
        let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
        current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
      }
      swap(&previous, &current)
    }

    return previous[b.count]
  }
}
