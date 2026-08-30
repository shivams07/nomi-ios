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
          ToolbarItem(placement: .primaryAction) {
            Button(skipTitle) {
              environment.firstRun.completeFirstRun()
            }
          }
        }
    }
    .background(NomiColor.surfaceCanvas)
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
      // `BackfillScreen` owns its own cancel/resume and reports completion only
      // by rendering it — there is no callback to hang the transition on — so
      // the way out is the toolbar button above, same as the connect step.
      BackfillScreen(mailConnectionService: environment.mailConnectionService, months: 6)
    }
  }

  /// "Skip" before anything has happened; "Done" once a backfill is running.
  ///
  /// **"Done" does not yet mean the work continues.** `BackfillScreen` cancels
  /// its own task in `.onDisappear`, so tapping this stops the scan the moment
  /// the screen goes away — the word promises something the app does not do.
  /// Removing that `onDisappear` is unit C (finding 7) and is not this unit's
  /// file; the comment is corrected rather than left asserting the outcome we
  /// want.
  ///
  /// What §D1 adds meanwhile is a floor, not the fix: a cancelled backfill
  /// leaves `MailStack.backfillIsUnfinished` set, so the next time the app is
  /// backgrounded `AppSyncCoordinator` asks iOS for the processing task and the
  /// remaining months are eventually fetched. Eventually, at a moment iOS
  /// chooses, with nothing on screen to say so. Once C lands, leaving the screen
  /// simply does not stop the scan and this note can go.
  private var skipTitle: String {
    switch step {
    case .connectMail: return "Skip"
    case .backfill: return "Done"
    }
  }
}
