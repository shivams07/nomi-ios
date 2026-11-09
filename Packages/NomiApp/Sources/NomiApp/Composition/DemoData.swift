#if DEBUG && (targetEnvironment(simulator) || os(macOS))
import Foundation
import NomiCore

/// The demo dataset: what a Debug simulator launched with `NOMI_DEMO_DATA=1`
/// seeds into an empty store, so the real screens have something to show.
///
/// **A value list and nothing else.** It names accounts, categories and budgets
/// by key or by name, not by id, because the ids are minted when the stores
/// create the rows. `DemoDataSeeder` is the only thing that turns it into rows,
/// and it does so through the stores.
///
/// **A function of `today`.** Months are taken relative to `today` in
/// `NomiCalendar.india`, and every date is noon IST so no timezone can move a row
/// onto the next day. A fixed `today` gives the same list every time.
///
/// **Compiled only where it can run.** A Debug simulator build, and a macOS
/// Debug build so `swift test` can check the list without a simulator. A device
/// or Release build never contains it, and `DemoDataSeeder.isRequested` is the
/// only reader of the environment variable.
///
/// The shape is taken from the approved artboards in
/// `specs/design/nomi-blue-restyle/project/` (Main, Insights, Ledger, Budgets,
/// Subscriptions, Cards, Rules, Detail). The category names are the app's
/// seeded ones, which differ from the artboards in places; see the PR.
struct DemoDataset: Equatable, Sendable {
  let accounts: [DemoAccount]
  let budgets: [DemoBudget]
  let rules: [DemoRule]
  let rows: [DemoRow]

  /// The dataset as of `today`. Current-month rows dated after `today` are left
  /// out, so the list never holds a future transaction.
  static func make(today: Date, calendar: Calendar = NomiCalendar.india) -> DemoDataset {
    let parts = calendar.dateComponents([.year, .month, .day], from: today)
    let anchor = Anchor(year: parts.year ?? 2026, month: parts.month ?? 1, day: parts.day ?? 1, calendar: calendar)
    return DemoDataset(
      accounts: accountList,
      budgets: budgetList,
      rules: ruleList,
      rows: rowSpecs.compactMap { $0.row(anchor) }
    )
  }

  // MARK: - Accounts

  /// Balances are the artboards' figures where they show one. The Cards artboard
  /// reads HDFC "Opening ₹1,20,000.00"; the cash wallet's opening is a demo
  /// figure, not one the artboards state.
  static let accountList: [DemoAccount] = [
    DemoAccount(
      key: "hdfc", displayName: "HDFC Savings", institution: "HDFC Bank",
      lastFour: "4471", kind: .bank, openingBalanceMinor: minor("120000")),
    DemoAccount(
      key: "icici", displayName: "ICICI Credit Card", institution: "ICICI Bank",
      lastFour: "9012", kind: .card, openingBalanceMinor: nil),
    DemoAccount(
      key: "cash", displayName: "Cash Wallet", institution: "",
      lastFour: "", kind: .wallet, openingBalanceMinor: minor("3500")),
  ]

  // MARK: - Budgets

  /// One under, one near (over 90%), one over, and one more under. Spend for
  /// the current month is in `DemoDataset.rowSpecs`; the figures are checked
  /// against the rows by the tests, not here.
  static let budgetList: [DemoBudget] = [
    DemoBudget(categoryName: "UPI & Food Delivery", amountMinor: minor("3000")),
    DemoBudget(categoryName: "Shopping", amountMinor: minor("5000")),
    DemoBudget(categoryName: "Ride-hailing", amountMinor: minor("2600")),
    DemoBudget(categoryName: "Groceries", amountMinor: minor("3000")),
  ]

  // MARK: - Rules

  /// Created after the rows, so each one re-applies across what is already in
  /// the store. The first mirrors the Rules artboard's `*ACME PAYROLL*` row,
  /// which is scoped to credits on HDFC (#106, #109). The second is the
  /// Netflix line the Ledger artboard files as Subscriptions; the app has no
  /// Subscriptions category, so it lands in Other.
  static let ruleList: [DemoRule] = [
    DemoRule(
      pattern: "*ACME PAYROLL*", categoryName: "Salary & Income",
      direction: .credit, accountKey: "hdfc", minAmountMinor: nil, maxAmountMinor: nil),
    DemoRule(
      pattern: "*NETFLIX*", categoryName: "Other",
      direction: nil, accountKey: nil, minAmountMinor: nil, maxAmountMinor: nil),
    DemoRule(
      pattern: "*BLUE TOKAI*", categoryName: "Shopping",
      direction: .debit, accountKey: "hdfc", minAmountMinor: minor("100"), maxAmountMinor: minor("2000")),
  ]

  // MARK: - Rows

  /// The rows, as specs relative to the anchor. Kept in one list so the three
  /// months read top to bottom the way the Ledger shows them.
  private static let rowSpecs: [RowSpec] = [
    // September (two months back)
    .pipeline("sep-salary", -2, 1, "hdfc", "ACME PAYROLL SEP 2026 SALARY", "38500", .credit, category: "Salary & Income", source: .email, sender: "hdfcbank.net", fragment: "4471"),
    .pipeline("sep-rent", -2, 5, "hdfc", "NEFT RENT RAJESH KUMAR", "18000", .debit, category: "Rent", source: .file),
    .pipeline("sep-netflix", -2, 6, "icici", "NETFLIX.COM", "649", .debit, category: "Other", source: .email, sender: "icicibank.com", fragment: "9012"),
    .pipeline("sep-amazon", -2, 8, "icici", "AMAZON PAY INDIA", "3460", .debit, category: "Shopping", source: .email, sender: "icicibank.com", fragment: "9012"),
    .pipeline("sep-zomato", -2, 10, "hdfc", "ZOMATO LTD UPI", "412", .debit, category: "UPI & Food Delivery", source: .file),
    .pipeline("sep-bigbasket", -2, 14, "hdfc", "BIGBASKET ONLINE", "1320", .debit, category: "Groceries", source: .file),
    .pipeline("sep-rapido", -2, 15, "icici", "RAPIDO RIDE", "520", .debit, category: "Ride-hailing", source: .email, sender: "icicibank.com", fragment: "9012"),
    .pipeline("sep-lic", -2, 16, "hdfc", "LIC OF INDIA PREMIUM", "2999", .debit, category: "Insurance", source: .file),
    .pipeline("sep-sip", -2, 18, "hdfc", "ZERODHA BROKING LTD", "5000", .debit, category: "SIP & Investments", source: .file),
    .pipeline("sep-atm", -2, 20, "hdfc", "ATM CASH WDL", "3000", .debit, category: "ATM Cash", source: .file),
    .pipeline("sep-bescom", -2, 25, "hdfc", "BESCOM ELECTRICITY BILL", "380", .debit, category: "Recharge & Utilities", source: .file),
    .manual("sep-cash-chai", -2, 28, "cash", "Chai and snacks", "600", .debit, category: "Other"),
    .pipeline("sep-pharmeasy", -2, 29, "hdfc", "PHARMEASY ORDER", "1250", .debit, category: "Health", source: .email, sender: "hdfcbank.net", fragment: "4471"),
    .pipeline("sep-interest", -2, 30, "hdfc", "INTEREST PAID", "412", .credit, category: nil, source: .file),

    // October (one month back)
    .pipeline("oct-salary", -1, 1, "hdfc", "ACME PAYROLL OCT SALARY", "38500", .credit, category: "Salary & Income", source: .email, sender: "hdfcbank.net", fragment: "4471"),
    .pipeline("oct-netflix", -1, 4, "icici", "NETFLIX.COM", "649", .debit, category: "Other", source: .email, sender: "icicibank.com", fragment: "9012"),
    .pipeline("oct-rent", -1, 5, "hdfc", "NEFT RENT RAJESH KUMAR", "18000", .debit, category: "Rent", source: .file),
    .pipeline("oct-myntra", -1, 6, "icici", "MYNTRA DESIGNS", "2450", .debit, category: "Shopping", source: .email, sender: "icicibank.com", fragment: "9012"),
    .pipeline("oct-zomato", -1, 8, "hdfc", "ZOMATO LTD UPI", "1820", .debit, category: "UPI & Food Delivery", source: .file),
    .pipeline("oct-ola", -1, 10, "icici", "OLACABS", "740", .debit, category: "Ride-hailing", source: .email, sender: "icicibank.com", fragment: "9012"),
    .pipeline("oct-irctc", -1, 12, "hdfc", "IRCTC TICKETING", "4250", .debit, category: nil, source: .file),
    .pipeline("oct-jiomart", -1, 14, "hdfc", "JIOMART ORDER", "2140", .debit, category: "Groceries", source: .file),
    .manual("oct-cash-auto", -1, 14, "cash", "Auto fare", "250", .debit, category: "Ride-hailing"),
    .pipeline("oct-jio", -1, 15, "icici", "JIO PREPAID RECHARGE", "215", .debit, category: "Recharge & Utilities", source: .email, sender: "icicibank.com", fragment: "9012"),
    .pipeline("oct-sip", -1, 18, "hdfc", "ZERODHA BROKING LTD", "5000", .debit, category: "SIP & Investments", source: .file),
    .pipeline("oct-atm", -1, 20, "hdfc", "ATM CASH WDL", "3000", .debit, category: "ATM Cash", source: .file),
    .pipeline("oct-instamart", -1, 22, "hdfc", "SWIGGY INSTAMART", "1630", .debit, category: "UPI & Food Delivery", source: .email, sender: "hdfcbank.net", fragment: "4471"),
    .pipeline("oct-cultfit", -1, 24, "icici", "CULT FIT MEMBERSHIP", "2499", .debit, category: nil, source: .email, sender: "icicibank.com", fragment: "9012"),
    .pipeline("oct-apollo", -1, 26, "hdfc", "APOLLO PHARMACY", "1100", .debit, category: "Health", source: .email, sender: "hdfcbank.net", fragment: "4471"),
    .pipeline("oct-hotel", -1, 27, "hdfc", "HOTEL BOOKING MAKEMYTRIP", "4900", .debit, category: nil, source: .file, review: .reason(.heuristic)),
    .pipeline("oct-imps", -1, 28, "hdfc", "IMPS P2P PRIYA SHARMA", "1050", .debit, category: nil, source: .file),
    .pipeline("oct-alert", -1, 29, "hdfc", "ALERT TRANSACTION SUMMARY", "480", .debit, category: nil, source: .email, sender: "hdfcbank.net", fragment: "4471", review: .reason(.unreadableDate)),
    .manual("oct-cash-papa", -1, 30, "cash", "Cash from Papa", "1000", .credit, category: nil),

    // November, to today
    .pipeline("nov-salary", 0, 1, "hdfc", "ACME PAYROLL NOV SALARY", "38500", .credit, category: "Salary & Income", source: .email, sender: "hdfcbank.net", fragment: "4471"),
    .pipeline("nov-unauth", 0, 2, "hdfc", "HDFC ALERT SPEND", "3000", .debit, category: nil, source: .email, sender: "hdfcbank.net", fragment: "4471", review: .reason(.unauthenticatedSender)),
    .pipeline("nov-swiggy", 0, 3, "hdfc", "SWIGGY ORDER", "648", .debit, category: "UPI & Food Delivery", source: .email, sender: "hdfcbank.net", fragment: "4471"),
    .pipeline("nov-amazon", 0, 3, "icici", "AMAZON.IN MARKETPLACE", "1299", .debit, category: "Shopping", source: .email, sender: "icicibank.com", fragment: "9012"),
    .pipeline("nov-github", 0, 3, "icici", "GITHUB INC", "12", .debit, category: nil, source: .email, sender: "icicibank.com", fragment: "9012", currency: "USD", minorOverride: 1200, review: .reason(.foreignCurrency)),
    .pipeline("nov-netflix", 0, 4, "icici", "NETFLIX.COM", "649", .debit, category: "Other", source: .email, sender: "icicibank.com", fragment: "9012"),
    .pipeline("nov-bigbasket", 0, 4, "hdfc", "BIGBASKET ONLINE", "2140", .debit, category: "Groceries", source: .file),
    .pipeline("nov-cc-out", 0, 5, "hdfc", "NEFT CC PAYMENT ICICI CARD", "18450", .debit, category: nil, source: .file, pair: "nov-card-bill"),
    .pipeline("nov-cc-in", 0, 5, "icici", "PAYMENT RECEIVED THANK YOU", "18450", .credit, category: nil, source: .email, sender: "icicibank.com", fragment: "9012", pair: "nov-card-bill"),
    .pipeline("nov-rent", 0, 5, "hdfc", "NEFT RENT RAJESH KUMAR", "18000", .debit, category: "Rent", source: .file),
    .pipeline("nov-dineout", 0, 6, "hdfc", "DINE OUT/SWIGGY/REF2", "68", .debit, category: "UPI & Food Delivery", source: .email, sender: "hdfcbank.net", fragment: "4471", review: .nearDuplicate),
    .pipeline("nov-dineout-2", 0, 7, "hdfc", "DINE OUT/SWIGGY/REF2", "68", .debit, category: "UPI & Food Delivery", source: .email, sender: "hdfcbank.net", fragment: "4471", absorbedInto: "nov-dineout"),
    .pipeline("nov-uber-1", 0, 6, "hdfc", "UBER INDIA TRIP", "500", .debit, category: "Ride-hailing", source: .email, sender: "hdfcbank.net", fragment: "4471"),
    .pipeline("nov-rapido", 0, 6, "icici", "RAPIDO RIDE", "320", .debit, category: "Ride-hailing", source: .email, sender: "icicibank.com", fragment: "9012"),
    .pipeline("nov-uber-2", 0, 7, "icici", "UBER INDIA TRIP", "780", .debit, category: "Ride-hailing", source: .email, sender: "icicibank.com", fragment: "9012"),
    .pipeline("nov-myntra", 0, 7, "icici", "MYNTRA DESIGNS", "2450", .debit, category: "Shopping", source: .email, sender: "icicibank.com", fragment: "9012"),
    .pipeline("nov-dominos", 0, 8, "hdfc", "DOMINOS PIZZA", "899", .debit, category: "UPI & Food Delivery", source: .email, sender: "hdfcbank.net", fragment: "4471"),
    .pipeline("nov-ola", 0, 8, "hdfc", "OLACABS", "845", .debit, category: "Ride-hailing", source: .email, sender: "hdfcbank.net", fragment: "4471"),
    .pipeline("nov-uber-3", 0, 8, "icici", "UBER INDIA TRIP", "1120", .debit, category: "Ride-hailing", source: .email, sender: "icicibank.com", fragment: "9012"),
    .pipeline("nov-flipkart", 0, 8, "icici", "FLIPKART INTERNET", "850", .debit, category: "Shopping", source: .email, sender: "icicibank.com", fragment: "9012"),
    .pipeline("nov-blue-tokai", 0, 8, "hdfc", "BLUE TOKAI COFFEE", "360", .debit, category: "Shopping", source: .file),
    .pipeline("nov-unidentified", 0, 8, nil, "UPI/SBI MERCHANT FOOD COURT", "1150", .debit, category: nil, source: .file, review: .reason(.unidentifiedAccount)),
    .manual("nov-cash-paper", 0, 9, "cash", "Newspaper", "240", .debit, category: "Other"),
    .pipeline("nov-unparseable", 0, 9, "hdfc", "CANDIDATE COULD NOT BE READ", "0", .debit, category: nil, source: .file, minorOverride: 0, review: .reason(.unparseable)),
  ]

  // MARK: - Money

  /// Rupees, parsed through the same `Decimal` path an intent amount takes, so
  /// every figure in this file is exact and goes through minor units. A bad
  /// literal here is a programming error, so it traps rather than being skipped.
  static func minor(_ rupees: String) -> Int {
    guard
      case .success(let value) = IntentDraftMapping.decimal(from: rupees),
      case .success(let paise) = IntentDraftMapping.minorUnits(from: value)
    else {
      preconditionFailure("DemoData amount is not a rupee amount: \(rupees)")
    }
    return paise
  }
}

// MARK: - Value types

struct DemoAccount: Equatable, Sendable {
  let key: String
  let displayName: String
  let institution: String
  let lastFour: String
  let kind: AccountKind
  /// `nil` is "the user never said". Set only where the artboards show one.
  let openingBalanceMinor: Int?
}

struct DemoBudget: Equatable, Sendable {
  let categoryName: String
  let amountMinor: Int
}

struct DemoRule: Equatable, Sendable {
  let pattern: String
  let categoryName: String
  let direction: Direction?
  /// The `DemoAccount.key` the rule is scoped to, or `nil` for any account.
  let accountKey: String?
  let minAmountMinor: Int?
  let maxAmountMinor: Int?
}

/// How a row reaches the store. Both are real write paths.
enum DemoRoute: Equatable, Sendable {
  /// Through `IngestPipeline`, the single ingest write path. Bank alerts and
  /// statement lines. Rules, transfer detection and dedupe all run here.
  case pipeline(source: IngestSource, senderDomain: String?, cardFragment: String?)
  /// Through `TransactionStore.add`, a manual entry. The category is the one
  /// the user chose, not one a rule picked.
  case manual
}

/// What the pipeline is told about a row's review state.
enum DemoReview: Equatable, Sendable {
  case none
  /// Set by the ingester at insert time, with its reason. The `NeedsReviewReason`
  /// cases that the Detail reason chip (#151) shows.
  case reason(NeedsReviewReason)
  /// Not set by the ingester. The pipeline flags it when the next row (its
  /// `absorbedInto` partner) is merged into it as a near duplicate (DEC-13).
  case nearDuplicate

  var isFlagged: Bool {
    if case .none = self { return false }
    return true
  }
}

struct DemoRow: Equatable, Sendable {
  /// Stable key. Also the `externalID` for pipeline rows, so a sync or a test
  /// can find the row it wrote.
  let id: String
  let route: DemoRoute
  /// `nil` is an unidentified account.
  let accountKey: String?
  let date: Date
  let narration: String
  let amountMinor: Int
  let currencyCode: String
  let direction: Direction
  /// The category a rule (or the manual choice) should leave the row in. `nil`
  /// is uncategorized. Transfer legs are `nil` by design.
  let categoryName: String?
  let review: DemoReview
  /// Set on the row the pipeline merges into the one named here. That row is not
  /// stored on its own.
  let absorbedInto: String?
  /// Both legs of one card-bill transfer share this key.
  let pairID: String?
}

// MARK: - Row specs

private struct Anchor {
  let year: Int
  let month: Int
  let day: Int
  let calendar: Calendar

  /// Noon IST on the day `monthOffset` months from the anchor's month, or `nil`
  /// when that day is after the anchor (a current-month row not yet happened).
  func date(monthOffset: Int, day: Int) -> Date? {
    if monthOffset == 0 && day > self.day { return nil }
    var year = self.year
    var month = self.month + monthOffset
    while month < 1 {
      month += 12
      year -= 1
    }
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
  }
}

/// One row, before it is dated against an anchor. A value, so the list stays
/// readable as a table.
private struct RowSpec {
  let id: String
  let route: DemoRoute
  let monthOffset: Int
  let day: Int
  let accountKey: String?
  let narration: String
  let amountMinor: Int
  let currencyCode: String
  let direction: Direction
  let categoryName: String?
  let review: DemoReview
  let absorbedInto: String?
  let pairID: String?

  func row(_ anchor: Anchor) -> DemoRow? {
    guard let date = anchor.date(monthOffset: monthOffset, day: day) else { return nil }
    return DemoRow(
      id: id, route: route, accountKey: accountKey, date: date,
      narration: narration, amountMinor: amountMinor, currencyCode: currencyCode,
      direction: direction, categoryName: categoryName, review: review,
      absorbedInto: absorbedInto, pairID: pairID)
  }

  static func pipeline(
    _ id: String, _ monthOffset: Int, _ day: Int, _ account: String?, _ narration: String,
    _ rupees: String, _ direction: Direction,
    category: String?, source: IngestSource, sender: String? = nil, fragment: String? = nil,
    currency: String = "INR", minorOverride: Int? = nil,
    review: DemoReview = .none, absorbedInto: String? = nil, pair: String? = nil
  ) -> RowSpec {
    RowSpec(
      id: id,
      route: .pipeline(source: source, senderDomain: sender, cardFragment: fragment),
      monthOffset: monthOffset, day: day, accountKey: account,
      narration: narration,
      amountMinor: minorOverride ?? DemoDataset.minor(rupees),
      currencyCode: currency, direction: direction,
      categoryName: category, review: review,
      absorbedInto: absorbedInto, pairID: pair)
  }

  static func manual(
    _ id: String, _ monthOffset: Int, _ day: Int, _ account: String, _ narration: String,
    _ rupees: String, _ direction: Direction, category: String?
  ) -> RowSpec {
    RowSpec(
      id: id, route: .manual, monthOffset: monthOffset, day: day, accountKey: account,
      narration: narration, amountMinor: DemoDataset.minor(rupees), currencyCode: "INR",
      direction: direction, categoryName: category, review: .none,
      absorbedInto: nil, pairID: nil)
  }
}
#endif
