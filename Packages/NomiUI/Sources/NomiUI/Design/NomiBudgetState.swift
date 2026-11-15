// clt-harness: include

/// The three budget states a bar, tag and label can show (F2a, I-17). Decided
/// by integer maths, so no `Double` ever decides a colour near a threshold.
public enum NomiBudgetState: Equatable, Sendable {
  case under
  case close
  case over

  /// `budgetMinor <= 0` is `.under`. Otherwise `.over` when `spent >= budget`,
  /// `.close` when `spent * 10 >= budget * 9` (90%, inclusive), else `.under`.
  public static func of(spentMinor: Int, budgetMinor: Int) -> NomiBudgetState {
    guard budgetMinor > 0 else { return .under }
    if spentMinor >= budgetMinor { return .over }
    if spentMinor * 10 >= budgetMinor * 9 { return .close }
    return .under
  }

  /// The word a tag shows for the state: nil under budget, "Close" or "Over".
  public var tagText: String? {
    switch self {
    case .under:
      return nil
    case .close:
      return String(localized: "Close", bundle: .module)
    case .over:
      return String(localized: "Over", bundle: .module)
    }
  }
}
