import NomiCore
import NomiUI
import SwiftUI

/// Sequences U7's two onboarding screens, which were built and never wired to
/// each other (§2.18(2): "`ConnectMailScreen` and `BackfillScreen` exist and
/// take an `onBackfillStart` closure, but ... nothing decides
/// onboarding-vs-main").
///
/// **Both steps can be left, and that is not a convenience.** Mail is one of two
/// ingest routes — the other is CSV/XLSX import — so a user who does not want to
/// hand this app a mailbox password must still reach the app. And connecting
/// can fail for a reason the user cannot fix on this screen: a Google app
/// password needs 2-Step Verification, and is not issued at all for
/// work/school or Advanced Protection accounts (R3). Without a way past, first
/// run would be a dead end for them.
struct OnboardingFlow: View {
  @ObservedObject var environment: AppEnvironment
  let step: OnboardingStep

  var body: some View {
    NavigationStack {
      content
        .toolbar {
          // The backfill step draws its own leave control (see `BackfillScreen`):
          // it is a full-bleed moment with no nav bar, and its white Done is the
          // exit once the scan finishes, so a second Done here would duplicate it.
          if step == .connectMail {
            ToolbarItem(placement: .primaryAction) {
              Button("Skip") {
                environment.firstRun.completeFirstRun()
              }
            }
          }
        }
    }
    .background(NomiColor.ground.ignoresSafeArea())
  }

  @ViewBuilder
  private var content: some View {
    switch step {
    case .connectMail:
      ConnectMailScreen(
        mailConnectionService: environment.mailConnectionService,
        // Fires when the screen sees `.connected`. `FirstRunGate.mailConnected`
        // ignores it once first run is done, because Settings pushes this same
        // screen later and re-entering a password there must not send a
        // returning user back into onboarding.
        onBackfillStart: { environment.firstRun.mailConnected() }
      )

    case .backfill:
      // Six months at first run (§1.3), and this is the hero screen the design
      // is most protective of: it "lands the user on the populated dashboard".
      //
      // "Done" leaves onboarding and nothing else. The scan carries on, and
      // `BackfillBanner` is what shows it once this screen is gone: unit C
      // removed `BackfillScreen`'s `.onDisappear` cancel, and `BackfillLifecycle`
      // covers the double-start that cancel was guarding against.
      //
      // Cancel on the screen is still a real pause. §D1 is the floor under it:
      // the cancelled backfill leaves `MailStack.backfillIsUnfinished` set, so the
      // next time the app is backgrounded `AppSyncCoordinator` asks iOS for the
      // processing task and the remaining months are eventually fetched.
      BackfillScreen(
        mailConnectionService: environment.mailConnectionService,
        months: 6,
        onFinish: { environment.firstRun.completeFirstRun() }
      )
    }
  }
}
