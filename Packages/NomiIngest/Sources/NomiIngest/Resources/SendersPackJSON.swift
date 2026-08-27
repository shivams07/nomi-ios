import Foundation

// The Layer-1 sender pack (§1.4).
//
// WHY THIS IS A SWIFT FILE AND NOT `senders.json`
// -----------------------------------------------
// The design specifies `Sources/NomiIngest/Resources/senders.json`, loaded as a
// bundled resource. That cannot be done as the repo currently stands: U0 froze
// `NomiIngest/Package.swift` with no `resources:` declaration, so SwiftPM never
// synthesises `Bundle.module` and a bundled JSON file is unreachable at runtime.
//
// Editing a frozen manifest is not mine to do, and it is not free either — the
// same target is built by U3's File tests, U4's Pipeline and U8's app, so a
// mistake there breaks three other people's branches. So the pack ships as JSON
// held in a Swift string, in the directory the design assigns it, decoded
// through exactly the Codable path a bundled file would use.
//
// To make it a real resource later, the whole change is:
//   1. move the literal below into `Resources/senders.json`
//   2. add `resources: [.process("Resources")]` to the NomiIngest target
//   3. in `SenderPack.bundled`, replace `SendersPackJSON.raw.data(using:)` with
//      `Bundle.module.url(forResource: "senders", withExtension: "json")`
// Nothing else moves. The CloudKit-hosted pack §1.4 wants later slots into the
// same place.
enum SendersPackJSON {
  static let raw = #"""    {
      "_readme": "PROVISIONAL PACK - NOT A CLAIM ABOUT WHICH BANKS THE USER HAS. These five entries are defaults chosen for coverage of the most commonly encountered Indian retail alert formats (design section 2.5). Nobody asked the user which banks he uses and nobody read his mail to find out (2.5.1, 2.5.2). The real list is discovered on the user's own device at first backfill, via SyncSummary.unmatchedSenders. If entries here are wrong the app still works: those senders fall through to the Layer-2 heuristic extractor, every row is flagged needsReview, and the domains show up in unmatchedSenders. Correcting an entry is a data edit to this file - no code change, no unit, no re-plan.",
      "version": 1,
      "candidateDomains": [
        "sbi.co.in",
        "alerts.sbi.co.in",
        "hdfcbank.net",
        "hdfcbank.com",
        "icicibank.com",
        "axisbank.com",
        "kotak.com",
        "americanexpress.com",
        "sbicard.com",
        "onecard.in",
        "idfcfirstbank.com",
        "yesbank.in",
        "pnb.co.in",
        "bankofbaroda.in",
        "canarabank.com",
        "unionbankofindia.bank",
        "indusind.com",
        "rblbank.com",
        "federalbank.co.in",
        "paytmbank.com",
        "phonepe.com",
        "npci.org.in"
      ],
      "candidateDomainTokens": [
        "bank",
        "card",
        "upi",
        "netbanking",
        "alerts",
        "paytm",
        "phonepe",
        "npci"
      ],
      "entries": [
        {
          "senderDomain": "sbi.co.in",
          "bankLabel": "State Bank of India",
          "subjectPattern": "(transaction|debit|credit|alert|txn)",
          "fieldRegexes": {
            "amount": "(?:debit|credit)(?:ed)?[^.]{0,40}?(?:by|of|for|with)\\s*(?:₹|INR|Rs\\.?)\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)",
            "date": "on\\s+(\\d{1,2}[-/]\\d{1,2}[-/]\\d{2,4})",
            "direction": "\\b(debited|credited|debit|credit)\\b",
            "accountFragment": "A/c\\s*(?:no\\.?)?\\s*[Xx*]+(\\d{4})",
            "narration": "((?:UPI|NEFT|IMPS|RTGS|ACH)[/-][^\\s]+(?:\\s[^\\s]*){0,3}|transfer to [A-Za-z0-9@._\\- ]{3,50})"
          },
          "accountHint": "State Bank of India"
        },
        {
          "senderDomain": "hdfcbank.net",
          "bankLabel": "HDFC Bank",
          "subjectPattern": "(transaction|debit|credit|alert|spent|txn)",
          "fieldRegexes": {
            "amount": "(?:₹|INR|Rs\\.?)\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)\\s*(?:has been\\s+|is\\s+|was\\s+)?(?:debited|credited|spent)",
            "date": "on\\s+(\\d{1,2}[-/]\\d{1,2}[-/]\\d{2,4})",
            "direction": "\\b(debited|credited|spent)\\b",
            "accountFragment": "(?:account|a/c|card)\\s*(?:no\\.?)?\\s*(?:ending\\s*)?[Xx*]*(\\d{4})",
            "narration": "(?:\\bat\\b|\\bto VPA\\b|\\btowards\\b)\\s+([A-Za-z0-9@._\\- ]{3,60}?)(?:\\s+on\\b|[.;]|$)"
          },
          "accountHint": "HDFC Bank"
        },
        {
          "senderDomain": "icicibank.com",
          "bankLabel": "ICICI Bank",
          "subjectPattern": "(transaction|debit|credit|alert|txn)",
          "fieldRegexes": {
            "amount": "(?:debited|credited)\\s*(?:with|by|for)?\\s*(?:₹|INR|Rs\\.?)\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)",
            "date": "on\\s+(\\d{1,2}[- ][A-Za-z]{3}[- ]\\d{2,4})",
            "direction": "\\b(debited|credited)\\b",
            "accountFragment": "(?:account|a/c|card)\\s*(?:no\\.?)?\\s*[Xx*]+(\\d{4})",
            "narration": "(?:\\bInfo:?|\\bat\\b|\\btowards\\b)\\s+([A-Za-z0-9@._\\-/ ]{3,60}?)(?:\\s+on\\b|[.;]|$)"
          },
          "accountHint": "ICICI Bank"
        },
        {
          "senderDomain": "axisbank.com",
          "bankLabel": "Axis Bank",
          "subjectPattern": "(transaction|debit|credit|alert|txn)",
          "fieldRegexes": {
            "amount": "(?:₹|INR|Rs\\.?)\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)\\s*(?:has been\\s+|is\\s+|was\\s+)?(?:debited|credited)",
            "date": "on\\s+(\\d{1,2}[-/]\\d{1,2}[-/]\\d{2,4})",
            "direction": "\\b(debited|credited)\\b",
            "accountFragment": "A/c\\s*(?:no\\.?)?\\s*[Xx*]+(\\d{4})",
            "narration": "(?:\\bInfo:?|\\bat\\b|\\btowards\\b)\\s+([A-Za-z0-9@._\\-/ ]{3,60}?)(?:\\s+on\\b|[.;]|$)"
          },
          "accountHint": "Axis Bank"
        },
        {
          "senderDomain": "kotak.com",
          "bankLabel": "Kotak Mahindra Bank",
          "subjectPattern": "(transaction|debit|credit|alert|spent|txn)",
          "fieldRegexes": {
            "amount": "(?:₹|INR|Rs\\.?)\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)\\s*(?:has been\\s+|is\\s+|was\\s+)?(?:debited|credited|spent)",
            "date": "on\\s+(\\d{1,2}[-/]\\d{1,2}[-/]\\d{2,4})",
            "direction": "\\b(debited|credited|spent)\\b",
            "accountFragment": "(?:card|a/c)\\s*(?:no\\.?)?\\s*[Xx*]+(\\d{4})",
            "narration": "(?:\\bat\\b|\\btowards\\b)\\s+([A-Za-z0-9@._\\- ]{3,60}?)(?:\\s+on\\b|[.;]|$)"
          },
          "accountHint": "Kotak Mahindra Bank"
        }
      ]
    }
    """#
}
