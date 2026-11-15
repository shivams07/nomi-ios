import NomiUI

/// Which Activity chip an `ActivityRequest` opens on (F3b, I-15). `LedgerScreen`
/// reads its chip once, when it is constructed, so `RootView` builds it with
/// `.id(activityRequestID)` and passes the chip from here.
enum ActivityRoute {
  static func chip(for request: ActivityRequest) -> LedgerChipSelection {
    switch request {
    case .toReview: return .needsReview
    case .uncategorized: return .uncategorized
    case .category(let id): return .category(id)
    case .all, .search: return .all
    }
  }
}
