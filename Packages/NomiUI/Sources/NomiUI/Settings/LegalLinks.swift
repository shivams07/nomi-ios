import Foundation

/// The legal and contact values the About screen shows.
///
/// Set by S9c once Shivam answers; nil hides the row. Until then the policy
/// and terms rows do not appear, and the footer does not appear either.
public enum LegalLinks {
  public static let privacyPolicy: URL? = nil
  public static let terms: URL? = nil
  public static let supportEmail = "singhshivamrakesh07@gmail.com"
  public static let publisherName: String? = nil
}
