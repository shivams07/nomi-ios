import NomiCore
import NomiUI
import SwiftUI

/// The Ledger tab's contents, and the single file U8b replaces.
///
/// **There is no Ledger screen in this repository yet.** §2.19(2): nobody was
/// ever assigned one — `TransactionRow` is U5's row and `RecentTransactionsCard`
/// is U9's five-row dashboard card, and `NomiUI/Ledger/**` fell between eight
/// units. It is now U14, Morgan's, in `NomiUI` where it can have previews and
/// `NomiUITests`; U8b then swaps it in here.
///
/// **This file exists so that swap is one file.** It takes the whole
/// `AppEnvironment` rather than the two or three stores a list would obviously
/// need, and that is deliberate: U8b's boundary is exactly
/// `LedgerTabHost.swift`, and its notes say that needing a second file is a
/// signal to escalate. If this host named specific stores and U14's screen took
/// a different set, U8b would have to edit `RootView` too. Taking the
/// environment means the call site never changes whatever U14 asks for.
///
/// **It says "not built yet" rather than showing something plausible.** Shaun
/// rejected pointing the tab at `RecentTransactionsCard` for the same reason: a
/// dashboard card alone in a tab reads as a bug, not as an unfinished screen.
/// An honest placeholder is the difference between a reviewer filing a defect
/// and a reviewer knowing where the work is.
struct LedgerTabHost: View {
  @ObservedObject var environment: AppEnvironment

  var body: some View {
    VStack(spacing: NomiSpacing.sm) {
      Image(systemName: "list.bullet.rectangle")
        .font(.system(size: 32, weight: .regular))
        .foregroundStyle(NomiColor.textQuaternary)
      Text("Ledger isn't built yet")
        .nomiTextStyle(.title)
        .foregroundStyle(NomiColor.textPrimary)
      Text("The full transaction list lands in a later update. Your recent transactions are on the Home tab.")
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.textTertiary)
        .multilineTextAlignment(.center)
    }
    .padding(NomiSpacing.screenGutter)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(NomiColor.surfaceCanvas)
    .navigationTitle("Ledger")
  }
}
