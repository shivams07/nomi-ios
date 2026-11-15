import Foundation

/// Which automatic routes Bring in your data offers in this build.
public enum OnboardingRoutes {
  /// `true` when A1 (alert intent) and A2 (automation guide) ship. Until then the
  /// Bank SMS alerts card is built and hidden, and the pill never names SMS
  /// (redesign plan section 8).
  public static let smsAvailable = false

  /// The pill's title when the email route is on. It is also the title the
  /// disabled pill shows when no automatic route is on.
  static var emailTitle: String {
    String(localized: "Continue with email", bundle: .module)
  }

  /// The title of the Bring in your data pill, or nil when the pill must be
  /// disabled.
  ///
  /// Both routes on, with SMS available, reads "Continue with SMS and email".
  /// Email on reads "Continue with email". SMS alone, and no route at all, have
  /// no title: the SMS route has no screen in this build, so SMS alone has
  /// nowhere to go.
  static func continueTitle(
    smsOn: Bool,
    emailOn: Bool,
    smsAvailable: Bool = OnboardingRoutes.smsAvailable
  ) -> String? {
    let sms = smsOn && smsAvailable
    if sms && emailOn {
      return String(localized: "Continue with SMS and email", bundle: .module)
    }
    if emailOn {
      return emailTitle
    }
    return nil
  }
}
