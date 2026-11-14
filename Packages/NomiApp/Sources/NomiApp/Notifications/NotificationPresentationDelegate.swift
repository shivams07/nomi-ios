import Foundation

#if canImport(UserNotifications)
  import UserNotifications

  /// Lets a budget alert show while the app is in the foreground.
  ///
  /// iOS suppresses a notification that arrives while its app is active unless
  /// the centre's delegate asks for it to be presented. Without this, an alert
  /// raised by a commit made in the foreground was recorded as fired and never
  /// seen, so the user was told nothing and the month was closed.
  ///
  /// It holds no state, which is what makes `@unchecked Sendable` true. The
  /// completion-handler form is the requirement iOS calls. An `async` method
  /// with the same name would not be a witness unless the SDK overlay provides
  /// one, and that would fail with no error.
  final class NotificationPresentationDelegate: NSObject, UNUserNotificationCenterDelegate,
    @unchecked Sendable
  {
    static let shared = NotificationPresentationDelegate()

    func userNotificationCenter(
      _ center: UNUserNotificationCenter,
      willPresent notification: UNNotification,
      withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
      completionHandler([.banner, .list, .sound])
    }
  }
#endif
