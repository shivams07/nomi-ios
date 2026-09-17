import Foundation
import NomiCore

/// Turns a spending total into a sentence Siri says out loud (W2-7).
///
/// Pure, and separate from `SpendingSummaryIntent`, for the reason
/// `IntentDraftMapping` is separate from `AddTransactionIntent`: an `AppIntent`
/// is not something `swift test` can run — it needs the intents runtime and a
/// host app. Every decision worth testing is here and the intent is left as
/// wiring.
///
/// **The amount is spelled out, not formatted.** A dialog is read aloud, and
/// "₹12,345.50" handed to a speech synthesiser is a string it has to guess at:
/// the rupee sign, the group separators and the decimal point are all
/// typography, not speech. So there are no digits in anything this produces —
/// `testTheDialogContainsNoDigitsAtAll` holds that literally.
enum IntentSummaryFormatting {

  /// The three periods the intent offers.
  ///
  /// Pure and free of `AppIntents`, with `SpendingSummaryPeriod` — the
  /// `AppEnum` Siri actually resolves against — mapping onto it in one place.
  /// The alternative is this file importing `AppIntents`, which is the import
  /// that makes it untestable.
  ///
  /// Only three, and no arbitrary month. A spoken parameter the user has to
  /// disambiguate ("which March?") is a worse shortcut than three they never
  /// have to.
  enum Window: Sendable, Hashable, CaseIterable {
    case thisMonth, lastMonth, thisFinancialYear
  }

  /// The financial year is India's: 1 April to 31 March, which is what
  /// `NomiCore.dateRange(for:)` already encodes and the only definition in this
  /// app.
  ///
  /// `now` and `calendar` are parameters and neither is defaulted to `.current`.
  /// A `= .current` default is a bug invisible from one machine: CI runs UTC,
  /// a phone in India does not, and a month boundary read off the wrong zone
  /// summarises the wrong month for everyone in the last five and a half hours
  /// of it.
  static func insightPeriod(for window: Window, now: Date, calendar: Calendar) -> InsightPeriod {
    let components = calendar.dateComponents([.year, .month], from: now)
    let year = components.year ?? 1970
    let month = components.month ?? 1

    switch window {
    case .thisMonth:
      return .month(year: year, month: month)
    case .lastMonth:
      return month == 1 ? .month(year: year - 1, month: 12) : .month(year: year, month: month - 1)
    case .thisFinancialYear:
      return .financialYear(startingYear: month >= 4 ? year : year - 1)
    }
  }

  /// How the period is named inside the sentence: "in September", "in this
  /// financial year".
  ///
  /// A month is named and not called "this month". The user asked about a
  /// period they already know, so the answer's job is to confirm *which* period
  /// it read — "you spent that much this month" is unfalsifiable by the person
  /// hearing it, and "you spent that much in September" is not.
  ///
  /// No year on the month. A person does not say one, and the only ambiguity
  /// this can produce is "last month" said in January, where December is still
  /// the only December they could mean.
  static func periodPhrase(for period: InsightPeriod, locale: Locale = spokenLocale) -> String {
    switch period {
    case .month(_, let month):
      let formatter = DateFormatter()
      formatter.locale = locale
      // `monthSymbols` and not a `dateFormat`: no date has to be constructed,
      // so there is no time zone in this at all.
      let symbols = formatter.monthSymbols ?? []
      guard (1...symbols.count).contains(month) else { return "that month" }
      return symbols[month - 1]
    case .financialYear:
      return "this financial year"
    case .trailingMonths(let months):
      return "the last \(spellOut(months, locale: locale)) months"
    case .allTime:
      return "all time"
    }
  }

  /// The whole sentence.
  ///
  /// Zero gets its own sentence rather than "you spent zero rupees", which is
  /// true, strange to hear, and indistinguishable from the app having failed to
  /// find anything.
  static func dialog(
    spentMinor: Int,
    period: InsightPeriod,
    categoryName: String?,
    locale: Locale = spokenLocale
  ) -> String {
    let when = periodPhrase(for: period, locale: locale)
    // "on Groceries", or nothing. Not "in Groceries": the category is what the
    // money went on, and "in" is already doing the period.
    let on = categoryName.map { " on \($0)" } ?? ""

    guard spentMinor != 0 else {
      return "You haven't spent anything\(on) in \(when)."
    }
    return "You spent \(spokenAmount(minor: spentMinor, locale: locale))\(on) in \(when)."
  }

  /// "twelve thousand three hundred forty-five rupees and fifty paise".
  ///
  /// Paise are mentioned only when there are any: a round figure said as
  /// "and zero paise" is how a person can tell a machine is talking.
  ///
  /// Singulars are handled because they are audible. "one rupees" is the kind
  /// of thing that makes a user stop using a shortcut.
  static func spokenAmount(minor: Int, locale: Locale = spokenLocale) -> String {
    let negative = minor < 0
    let magnitude = abs(minor)
    let rupees = magnitude / 100
    let paise = magnitude % 100

    var parts: [String] = []
    if rupees != 0 || paise == 0 {
      parts.append("\(spellOut(rupees, locale: locale)) \(rupees == 1 ? "rupee" : "rupees")")
    }
    if paise != 0 {
      parts.append("\(spellOut(paise, locale: locale)) \(paise == 1 ? "paisa" : "paise")")
    }

    let spoken = parts.joined(separator: " and ")
    // A spend total is a sum of positive amounts and cannot be negative today.
    // Saying so rather than dropping the sign: a minus that goes silent here
    // would read as a plausible figure with no hint anything was wrong.
    return negative ? "minus \(spoken)" : spoken
  }

  /// The locale every spoken string here is built in.
  ///
  /// Pinned, and not `.current`. Two reasons, and the second is the one that
  /// matters: the dialog is English regardless of the device (there is no
  /// localisation in this app yet, and a half-translated sentence is worse than
  /// an English one), and spell-out rules differ between English locales — an
  /// `en_GB`-family locale says "three hundred **and** forty-five" where `en_US`
  /// says "three hundred forty-five". Both are natural; only a fixed one is
  /// assertable, and a dialog that changes wording with the device's region is
  /// a test that passes on one machine.
  ///
  /// `en_IN` would be the obvious choice for an India-first app, and the reason
  /// it is not used is only that I could not establish which of the two
  /// spell-out families it inherits without a toolchain to ask. The difference
  /// is one word of no consequence to a listener and every difference to an
  /// exact assertion. A reviewer who knows the answer should feel free to
  /// change this one line; the tests will say immediately if it moves the
  /// wording.
  static let spokenLocale = Locale(identifier: "en_US")

  private static func spellOut(_ value: Int, locale: Locale) -> String {
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .spellOut
    // A fallback that is still words, never digits. `spellOut` returning `nil`
    // would otherwise be the one path that puts a numeral into a spoken
    // sentence.
    return formatter.string(from: NSNumber(value: value)) ?? "an unknown number of"
  }
}
