import NomiCore

/// Whether `RootView` should draw `BackfillBanner` above the tab content.
///
/// `unfinished` is `MailStack.backfillIsUnfinished` — the persisted "a scan
/// started and has not completed" flag. `progress` is the latest tick off
/// `mailConnectionService.backfillProgress`, or `nil` before the first tick
/// has arrived. A `nil` tick with an unfinished scan still shows the banner —
/// there is progress to report, it just has not landed yet.
///
/// Completion is checked here rather than reused from `NomiUI`'s
/// `BackfillMath.isComplete` — that type is `internal` to its module, and
/// duplicating the one-line arithmetic across the module boundary is cheaper
/// than exporting it.
enum BackfillBannerVisibility {
  static func shouldShow(progress: BackfillProgress?, unfinished: Bool) -> Bool {
    guard unfinished else { return false }
    guard let progress else { return true }
    return !(progress.total > 0 && progress.scanned >= progress.total)
  }
}
