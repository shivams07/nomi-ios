// clt-harness: include

/// What "show the Ledger" does to the root's navigation state (FU-1). Pure, so
/// the target tab and the Home reset are asserted without rendering `RootView`.
enum ShowLedgerRoute {
  struct Outcome: Equatable {
    let selection: RootTab
    /// Whether Home's stack is reset to its root. Both controls sit on Home's
    /// stack (the Recent header, and Import, which Settings pushes), so without
    /// the reset the Ledger tab would come back under a pushed screen.
    let clearsHomeStack: Bool
  }

  static func outcome() -> Outcome {
    Outcome(selection: .ledger, clearsHomeStack: true)
  }
}
