import Foundation

/// Copy for a recurring row (S7).
enum RecurringCopy {
  /// The bills a household has to pay, read from the category name. A match on any
  /// of these is "Due"; everything else "Renews"; no category at all is "Next".
  private static let dueWords = ["rent", "emi", "loan", "insurance", "utilit", "bill"]

  static func verb(categoryName: String?) -> String {
    guard let categoryName else { return "Next" }
    let name = categoryName.lowercased()
    return dueWords.contains { name.contains($0) } ? "Due" : "Renews"
  }

  /// The row's second line: "Due 5 Dec · monthly". The day is read in the
  /// calendar that built the date, not the machine's zone, so a date near
  /// midnight keeps its day.
  static func subtitle(verb: String, nextExpected: Date, calendar: Calendar) -> String {
    "\(verb) \(PlanLogic.dayMonth(nextExpected, calendar: calendar)) · monthly"
  }
}
