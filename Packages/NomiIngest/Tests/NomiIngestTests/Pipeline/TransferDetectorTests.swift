import Foundation
import NomiCore
import SwiftData
import XCTest

@testable import NomiIngest

/// DEC-05 A-05 items 5 to 8 as fixtures, on the pure detector (TR5). Every amount
/// is minor units (20,000.00 is 2_000_000). Every group id below was computed in
/// stdlib Python (`hashlib`, `uuid`) from the two row UUIDs, not from Swift.
///
/// Fixture F's accounts: savings S (bank, last four 2210) and card C (card,
/// last four 4471). Days are 2026-11-n in Asia/Kolkata.
final class TransferDetectorTests: XCTestCase {

  private let calendar = Fixture.calendar

  private let savingsAccount = UUID(uuidString: "AC000000-0000-0000-0000-00000000000A")!
  private let cardAccount = UUID(uuidString: "AC000000-0000-0000-0000-00000000000C")!
  /// A second bank account, so the card-kind test changes only the credit's kind.
  private let otherBankAccount = UUID(uuidString: "AC000000-0000-0000-0000-00000000000B")!

  private lazy var accounts: [UUID: TransferAccount] = [
    savingsAccount: TransferAccount(kind: .bank, lastFour: "2210"),
    cardAccount: TransferAccount(kind: .card, lastFour: "4471"),
    otherBankAccount: TransferAccount(kind: .bank, lastFour: "9900"),
  ]

  /// Fixture F's rows. S is the savings debit, C the card credit, CD the card's
  /// own debit for Amazon (the purchase the bill pays for).
  private let s = UUID(uuidString: "5A000000-0000-0000-0000-000000000001")!
  private let c = UUID(uuidString: "C0000000-0000-0000-0000-000000000002")!
  private let cd = UUID(uuidString: "C0000000-0000-0000-0000-000000000003")!
  private let s2 = UUID(uuidString: "5A000000-0000-0000-0000-000000000004")!
  private let c2 = UUID(uuidString: "C0000000-0000-0000-0000-000000000005")!

  /// Python: `make_pair(S, C)` = `68b3c33e-3c4f-86e1-26f9-fa94a30c05b4`.
  private let pairGroupSC = UUID(uuidString: "68B3C33E-3C4F-86E1-26F9-FA94A30C05B4")!

  // MARK: - Builders

  /// A row on 2026-11-`day` at noon. Defaults: INR, 20,000.00, email source,
  /// no transfer state.
  private func leg(
    _ id: UUID,
    _ direction: Direction,
    _ narration: String,
    day: Int = 10,
    amount: Int = 2_000_000,
    currency: String = "INR",
    account: UUID?,
    groupID: UUID? = nil,
    sourceRaw: String? = nil
  ) -> TransactionSnapshot {
    TransactionSnapshot(
      id: id,
      date: Fixture.date(String(format: "2026-11-%02d 12:00", day)),
      descriptionText: narration,
      normalizedDescription: narration.uppercased(),
      amountMinor: amount,
      currencyCode: currency,
      directionRaw: direction.rawValue,
      accountID: account,
      sourceRaw: IngestSource.email.rawValue,
      dedupeKey: id.uuidString,
      createdAt: Fixture.commitTime,
      updatedAt: Fixture.commitTime,
      senderDomain: nil,
      cardFragment: nil,
      needsReviewReason: nil,
      transferGroupID: groupID,
      transferSourceRaw: sourceRaw
    )
  }

  /// Fixture F's bill pair: S debit 10 Nov, C credit 11 Nov, both 20,000.00.
  private func fixtureF(
    debitNarration: String = "HDFC CREDIT CARD PAYMENT",
    creditNarration: String = "PAYMENT RECEIVED - THANK YOU"
  ) -> [TransactionSnapshot] {
    [
      leg(s, .debit, debitNarration, day: 10, account: savingsAccount),
      leg(c, .credit, creditNarration, day: 11, account: cardAccount),
    ]
  }

  private func detect(_ rows: [TransactionSnapshot]) -> [TransferMark] {
    TransferDetector.detect(rows: rows, accounts: accounts, calendar: calendar)
  }

  /// The rows with the marks written onto them, as `applyTransferMarks` would
  /// write them. Only the transfer pair changes.
  private func applying(_ marks: [TransferMark], to rows: [TransactionSnapshot]) -> [TransactionSnapshot] {
    rows.map { row in
      guard let mark = marks.first(where: { $0.id == row.id }) else { return row }
      var copy = row
      copy.transferGroupID = mark.pair.groupID
      copy.transferSourceRaw = mark.pair.sourceRaw
      return copy
    }
  }

  private func assertNoMarks(_ rows: [TransactionSnapshot], _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(detect(rows), [], message, file: file, line: line)
  }

  // MARK: - Fixture F (A-05 item 1 at the detector)

  /// Fixture F marks exactly its bill pair. The card's own Amazon debit is not
  /// a leg: it is on the card account itself, and a same-direction row.
  func testFixtureFMarksTheBillPairAndNothingElse() {
    let rows = fixtureF() + [leg(cd, .debit, "AMAZON", day: 9, account: cardAccount)]

    let marks = detect(rows)

    XCTAssertEqual(marks.count, 2)
    XCTAssertEqual(Set(marks.map(\.id)), [s, c])
    XCTAssertEqual(Set(marks.map(\.groupID)), [pairGroupSC])
    XCTAssertEqual(marks.first { $0.id == s }?.partnerID, c)
    XCTAssertEqual(marks.first { $0.id == c }?.partnerID, s)
    XCTAssertEqual(marks.map(\.pair.sourceRaw), ["auto", "auto"])
  }

  /// The group id is order-independent: the credit's and debit's ids in either
  /// order give the same value the mark carries.
  func testTheGroupIdIsThePythonComputedPairId() {
    XCTAssertEqual(TransferGroupID.make(s, c), pairGroupSC)
    XCTAssertEqual(TransferGroupID.make(c, s), pairGroupSC)
  }

  /// A second run over the marked rows finds nothing: marked legs are not free.
  /// Idempotent (A-05 item 8).
  func testASecondRunOverTheMarkedRowsWritesNothing() {
    let first = detect(fixtureF())
    XCTAssertEqual(first.count, 2)

    let marked = applying(first, to: fixtureF())

    XCTAssertEqual(detect(marked), [])
  }

  // MARK: - Window (DEC-05 "within 3 calendar days")

  /// Three calendar days apart is in (8 Nov against 11 Nov); four is out (7 Nov).
  /// Python: |11 - 8| = 3, |11 - 7| = 4.
  func testThreeCalendarDaysPairsAndFourDoesNot() {
    let inWindow = [
      leg(s, .debit, "HDFC CREDIT CARD PAYMENT", day: 8, account: savingsAccount),
      leg(c, .credit, "PAYMENT RECEIVED", day: 11, account: cardAccount),
    ]
    XCTAssertEqual(Set(detect(inWindow).map(\.id)), [s, c])

    let outOfWindow = [
      leg(s, .debit, "HDFC CREDIT CARD PAYMENT", day: 7, account: savingsAccount),
      leg(c, .credit, "PAYMENT RECEIVED", day: 11, account: cardAccount),
    ]
    assertNoMarks(outOfWindow, "four days apart must not pair")
  }

  // MARK: - Positive narration evidence (at least three per leg)

  /// Credit leg evidence alone is enough: the debit narration is neutral.
  func testEachCreditNarrationIsEvidenceOnItsOwn() {
    let creditPositives = [
      "PAYMENT RECEIVED - THANK YOU",
      "Thank you for payment",
      "HDFC BILL PAYMENT RCVD",
      "CC PAYMENT RECD",
    ]
    for narration in creditPositives {
      let rows = [
        leg(s, .debit, "NEFT RAMESH", day: 10, account: savingsAccount),
        leg(c, .credit, narration, day: 11, account: cardAccount),
      ]
      XCTAssertEqual(Set(detect(rows).map(\.id)), [s, c], "credit narration: \(narration)")
    }
  }

  /// Debit leg evidence alone is enough: the credit narration is neutral. The
  /// last-four case names the card by its digits, not by a phrase.
  func testEachDebitNarrationIsEvidenceOnItsOwn() {
    let debitPositives = [
      "HDFC CREDIT CARD PAYMENT",
      "CARD BILL PAID",
      "ICICI CARD PAYMENT",
      "NEFT TO 4471 RAMESH",
      "ACH 4471 DR",
    ]
    for narration in debitPositives {
      let rows = [
        leg(s, .debit, narration, day: 10, account: savingsAccount),
        leg(c, .credit, "REFUND - Amazon", day: 11, account: cardAccount),
      ]
      XCTAssertEqual(Set(detect(rows).map(\.id)), [s, c], "debit narration: \(narration)")
    }
  }

  // MARK: - Negative narration evidence (at least three per leg)

  /// Neither leg carries evidence, so no pair, whatever the other facts. Every
  /// combination below is the same amount, day and accounts, so only the
  /// narration decides.
  func testNoNarrationEvidenceOnEitherLegMarksNothing() {
    let creditNegatives = ["REFUND - Amazon", "SALARY CREDIT", "UPI CREDIT RAMESH"]
    let debitNegatives = [
      "NEFT RAMESH",
      "GIFT CARD PURCHASE",
      "ACH 14471 DR",
      "NEFT 0044 RAMESH",
      "UPI/SWIGGY 4471X",
    ]
    for credit in creditNegatives {
      for debit in debitNegatives {
        let rows = [
          leg(s, .debit, debit, day: 10, account: savingsAccount),
          leg(c, .credit, credit, day: 11, account: cardAccount),
        ]
        assertNoMarks(rows, "debit \"\(debit)\" with credit \"\(credit)\"")
      }
    }
  }

  /// A-05 item 5. A card credit of 20,000.00 "REFUND - Amazon" on the same day
  /// as an unrelated savings debit of 20,000.00 is not paired.
  func testARefundOnTheSameDayIsNotPairedWithAnUnrelatedDebit() {
    let rows = [
      leg(s, .debit, "NEFT RAMESH", day: 11, account: savingsAccount),
      leg(c, .credit, "REFUND - Amazon", day: 11, account: cardAccount),
    ]
    assertNoMarks(rows)
  }

  // MARK: - Ambiguity (A-05 item 6)

  /// Two savings debits of 5,000.00 and one card credit of 5,000.00 inside the
  /// window mark nothing. The credit has two base-eligible partners.
  func testTwoDebitsAgainstOneCreditMarksNothing() {
    let rows = [
      leg(s, .debit, "HDFC CREDIT CARD PAYMENT", day: 9, amount: 500_000, account: savingsAccount),
      leg(s2, .debit, "HDFC CREDIT CARD PAYMENT", day: 10, amount: 500_000, account: savingsAccount),
      leg(c, .credit, "PAYMENT RECEIVED - THANK YOU", day: 11, amount: 500_000, account: cardAccount),
    ]
    assertNoMarks(rows)
  }

  /// The mirror: one savings debit and two card credits. The debit has two
  /// partners, so nothing is marked on either side.
  func testOneDebitAgainstTwoCreditsMarksNothing() {
    let rows = [
      leg(s, .debit, "HDFC CREDIT CARD PAYMENT", day: 10, amount: 500_000, account: savingsAccount),
      leg(c, .credit, "PAYMENT RECEIVED - THANK YOU", day: 10, amount: 500_000, account: cardAccount),
      leg(c2, .credit, "PAYMENT RECEIVED - THANK YOU", day: 11, amount: 500_000, account: cardAccount),
    ]
    assertNoMarks(rows)
  }

  /// Uniqueness is counted on the base test, so a lookalike with no narration
  /// still blocks a mark. With the narration-free second debit present, the
  /// pair of fixture F is not marked.
  func testANarrationFreeLookalikeStillBlocksAUniqueMatch() {
    let rows = fixtureF() + [leg(s2, .debit, "NEFT RAMESH", day: 10, account: savingsAccount)]
    assertNoMarks(rows)
  }

  /// TR3. An unrecognised row competes for a match. Fixture F, plus a second
  /// savings debit of the same amount on 12 Nov whose pair this build cannot
  /// read, is not marked: the lookalike could be the real payment. The same row
  /// with `(nil, rejected)` is decided, so it does not compete, and the pair is
  /// marked.
  func testAnUnrecognisedLookalikeBlocksTheMatch() {
    let unrecognised = leg(s2, .debit, "HDFC CREDIT CARD PAYMENT", day: 12,
                           account: savingsAccount, sourceRaw: "zzz")
    assertNoMarks(fixtureF() + [unrecognised], "an unrecognised lookalike must block the match")

    let rejected = leg(s2, .debit, "HDFC CREDIT CARD PAYMENT", day: 12,
                       account: savingsAccount, sourceRaw: TransferSource.rejected.rawValue)
    XCTAssertEqual(Set(detect(fixtureF() + [rejected]).map(\.id)), [s, c])
  }

  // MARK: - INR only (A-05 item 7)

  /// A pair of USD rows is never marked, however the narration reads.
  func testAUSDPairIsNeverMarked() {
    let rows = [
      leg(s, .debit, "HDFC CREDIT CARD PAYMENT", day: 10, currency: "USD", account: savingsAccount),
      leg(c, .credit, "PAYMENT RECEIVED - THANK YOU", day: 11, currency: "USD", account: cardAccount),
    ]
    assertNoMarks(rows)
  }

  /// One leg in USD and one in INR is not a pair either.
  func testAMixedCurrencyPairIsNeverMarked() {
    let rows = [
      leg(s, .debit, "HDFC CREDIT CARD PAYMENT", day: 10, account: savingsAccount),
      leg(c, .credit, "PAYMENT RECEIVED - THANK YOU", day: 11, currency: "USD", account: cardAccount),
    ]
    assertNoMarks(rows)
  }

  // MARK: - Account conditions

  /// The credit leg must sit on a card. The same narration on a bank account is
  /// a transfer between two banks, which is manual only in this release.
  func testTheCreditLegMustBeOnACard() {
    let rows = [
      leg(s, .debit, "HDFC CREDIT CARD PAYMENT", day: 10, account: savingsAccount),
      leg(s2, .credit, "PAYMENT RECEIVED - THANK YOU", day: 11, account: otherBankAccount),
    ]
    assertNoMarks(rows)
  }

  /// A credit leg whose account the caller did not supply is not a card as far
  /// as the detector knows. Nothing is marked.
  func testAnAccountMissingFromTheFactsBlocksThePair() {
    let unknown = UUID(uuidString: "AC000000-0000-0000-0000-0000000000FF")!
    let rows = [
      leg(s, .debit, "HDFC CREDIT CARD PAYMENT", day: 10, account: savingsAccount),
      leg(c, .credit, "PAYMENT RECEIVED - THANK YOU", day: 11, account: unknown),
    ]
    assertNoMarks(rows)
  }

  /// A leg with no account is never paired (DEC-05 Amendment 1: a row with no
  /// account is marked alone, which here means not at all).
  func testARowWithNoAccountIsNeverPaired() {
    assertNoMarks([
      leg(s, .debit, "HDFC CREDIT CARD PAYMENT", day: 10, account: nil),
      leg(c, .credit, "PAYMENT RECEIVED - THANK YOU", day: 11, account: cardAccount),
    ])
    assertNoMarks([
      leg(s, .debit, "HDFC CREDIT CARD PAYMENT", day: 10, account: savingsAccount),
      leg(c, .credit, "PAYMENT RECEIVED - THANK YOU", day: 11, account: nil),
    ])
  }

  /// Two legs on the same account are not a transfer between accounts.
  func testTwoLegsOnTheSameAccountAreNeverPaired() {
    assertNoMarks([
      leg(s, .debit, "HDFC CREDIT CARD PAYMENT", day: 10, account: cardAccount),
      leg(c, .credit, "PAYMENT RECEIVED - THANK YOU", day: 11, account: cardAccount),
    ])
  }

  /// A single row with no partner is never marked (DEC-05).
  func testASingleRowIsNeverMarked() {
    assertNoMarks(Array(fixtureF().prefix(1)))
    assertNoMarks([leg(c, .credit, "PAYMENT RECEIVED - THANK YOU", day: 11, account: cardAccount)])
  }

  // MARK: - Manual, rejected and unrecognised rows are never touched (A-05 item 8)

  /// A manual leg is not free, so fixture F with its credit already marked by
  /// the user is left alone.
  func testAManualLegIsNeverRemarked() {
    let manualGroup = TransferGroupID.make(single: c)
    let rows = [
      leg(s, .debit, "HDFC CREDIT CARD PAYMENT", day: 10, account: savingsAccount),
      leg(c, .credit, "PAYMENT RECEIVED - THANK YOU", day: 11, account: cardAccount,
          groupID: manualGroup, sourceRaw: TransferSource.manual.rawValue),
    ]
    assertNoMarks(rows)
  }

  /// A debit the user said is not a transfer (`rejected`) is never marked again.
  func testARejectedLegIsNeverMarkedAgain() {
    let rows = [
      leg(s, .debit, "HDFC CREDIT CARD PAYMENT", day: 10, account: savingsAccount,
          sourceRaw: TransferSource.rejected.rawValue),
      leg(c, .credit, "PAYMENT RECEIVED - THANK YOU", day: 11, account: cardAccount),
    ]
    assertNoMarks(rows)
  }

  /// An auto pair already written is not marked a second time, whether or not
  /// the two rows carry the same group.
  func testAnAutoPairAlreadyWrittenIsNotMarkedAgain() {
    let rows = [
      leg(s, .debit, "HDFC CREDIT CARD PAYMENT", day: 10, account: savingsAccount,
          groupID: pairGroupSC, sourceRaw: TransferSource.auto.rawValue),
      leg(c, .credit, "PAYMENT RECEIVED - THANK YOU", day: 11, account: cardAccount,
          groupID: pairGroupSC, sourceRaw: TransferSource.auto.rawValue),
    ]
    assertNoMarks(rows)
  }

  /// A row whose pair this build cannot read (Amendment 3) is not free, so it
  /// is never claimed, even by a perfect partner.
  func testAnUnrecognisedLegIsNeverClaimed() {
    let rows = [
      leg(s, .debit, "HDFC CREDIT CARD PAYMENT", day: 10, account: savingsAccount,
          sourceRaw: "zzz"),
      leg(c, .credit, "PAYMENT RECEIVED - THANK YOU", day: 11, account: cardAccount),
    ]
    assertNoMarks(rows)
  }

  /// A debit with a group id but no source is `(id, nil)`, unrecognised too.
  func testAGroupWithNoSourceIsNeverClaimed() {
    let rows = [
      leg(s, .debit, "HDFC CREDIT CARD PAYMENT", day: 10, account: savingsAccount, groupID: pairGroupSC),
      leg(c, .credit, "PAYMENT RECEIVED - THANK YOU", day: 11, account: cardAccount),
    ]
    assertNoMarks(rows)
  }

  // MARK: - Input hygiene

  /// The same row id twice is one row: the first occurrence is used, so the
  /// pair is still marked once and the duplicate does not make it ambiguous.
  func testADuplicatedRowIdIsCountedOnce() {
    let rows = fixtureF() + [leg(s, .debit, "HDFC CREDIT CARD PAYMENT", day: 10, account: savingsAccount)]
    let marks = detect(rows)
    XCTAssertEqual(Set(marks.map(\.id)), [s, c])
    XCTAssertEqual(marks.count, 2)
  }

  /// Output is sorted by leg id, so the same rows in any order give the same marks.
  func testTheSameRowsInAnyOrderGiveTheSameMarks() {
    let forward = detect(fixtureF())
    let backward = detect(Array(fixtureF().reversed()))
    XCTAssertEqual(forward, backward)
  }

  /// `TransferMark.pair` is what the store writes: the group and `auto`.
  func testAMarkCarriesTheAutoPair() {
    let mark = TransferMark(id: s, partnerID: c, groupID: pairGroupSC)
    XCTAssertEqual(mark.pair, TransferPair(groupID: pairGroupSC, sourceRaw: "auto"))
  }

  // MARK: - Whole-pair writes (TR4, TR5)

  private let pairAuto = TransferPair(groupID: UUID(uuidString: "68B3C33E-3C4F-86E1-26F9-FA94A30C05B4")!, sourceRaw: "auto")

  /// The baseline write for fixture F: both legs read unmarked on their accounts.
  /// S sorts first ("5A…" < "C0…"), so S is `first`.
  private func baselineWrite(sReadPair: TransferPair? = TransferPair(groupID: nil, sourceRaw: nil),
                             cReadPair: TransferPair? = TransferPair(groupID: nil, sourceRaw: nil),
                             sReadAccount: UUID? = nil,
                             cReadAccount: UUID? = nil) -> TransferPairWrite {
    TransferPairWrite(
      first: TransferLegState(id: s, accountID: sReadAccount ?? savingsAccount, pair: sReadPair),
      second: TransferLegState(id: c, accountID: cReadAccount ?? cardAccount, pair: cReadPair),
      pair: pairAuto
    )
  }

  private let unmarked = TransferPair(groupID: nil, sourceRaw: nil)

  /// TR5. One true baseline, then each single change gives false.
  func testMayWriteNeedsEveryCondition() {
    let write = baselineWrite()
    let sNow = TransferLegState(id: s, accountID: savingsAccount, pair: unmarked)
    let cNow = TransferLegState(id: c, accountID: cardAccount, pair: unmarked)
    XCTAssertTrue(write.mayWrite(firstNow: sNow, secondNow: cNow), "baseline must be writable")

    // Read pair nil, on either leg: a snapshot not read from the store.
    XCTAssertFalse(baselineWrite(sReadPair: nil).mayWrite(firstNow: sNow, secondNow: cNow))
    XCTAssertFalse(baselineWrite(cReadPair: nil).mayWrite(firstNow: sNow, secondNow: cNow))

    // Current pair now manual, on either leg.
    let manual = TransferPair(groupID: UUID(), sourceRaw: "manual")
    XCTAssertFalse(write.mayWrite(
      firstNow: TransferLegState(id: s, accountID: savingsAccount, pair: manual), secondNow: cNow))
    XCTAssertFalse(write.mayWrite(
      firstNow: sNow, secondNow: TransferLegState(id: c, accountID: cardAccount, pair: manual)))

    // Current pair now rejected, on either leg.
    let rejected = TransferPair(groupID: nil, sourceRaw: "rejected")
    XCTAssertFalse(write.mayWrite(
      firstNow: TransferLegState(id: s, accountID: savingsAccount, pair: rejected), secondNow: cNow))
    XCTAssertFalse(write.mayWrite(
      firstNow: sNow, secondNow: TransferLegState(id: c, accountID: cardAccount, pair: rejected)))

    // Account changed since the read, on either leg.
    let other = UUID()
    XCTAssertFalse(write.mayWrite(
      firstNow: TransferLegState(id: s, accountID: other, pair: unmarked), secondNow: cNow))
    XCTAssertFalse(write.mayWrite(
      firstNow: sNow, secondNow: TransferLegState(id: c, accountID: other, pair: unmarked)))

    // Account nil at the read: the leg cannot have been eligible.
    XCTAssertFalse(baselineWrite(sReadAccount: nil).mayWrite(
      firstNow: TransferLegState(id: s, accountID: nil, pair: unmarked), secondNow: cNow))

    // The pair to write is not auto.
    let writeManual = TransferPairWrite(
      first: write.first, second: write.second,
      pair: TransferPair(groupID: pairGroupSC, sourceRaw: "manual"))
    XCTAssertFalse(writeManual.mayWrite(firstNow: sNow, secondNow: cNow))

    // Equal leg ids.
    let same = TransferPairWrite(first: write.first, second: write.first, pair: pairAuto)
    XCTAssertFalse(same.mayWrite(firstNow: sNow, secondNow: sNow))
  }

  /// TR5. Fixture F's two marks, read, make one write. It is kept only when a
  /// touched row is one of its legs. A lone mark, a missing read or no touched
  /// row gives nothing.
  func testWritesKeepsOnlyWholePairsWithATouchedLeg() {
    let marks = detect(fixtureF())
    let states = [
      s: TransferLegState(id: s, accountID: savingsAccount, pair: unmarked),
      c: TransferLegState(id: c, accountID: cardAccount, pair: unmarked),
    ]

    let kept = TransferPairWrite.writes(from: marks, readStates: states, touching: [s])
    XCTAssertEqual(kept.count, 1)
    XCTAssertEqual(kept.first?.first.id, s, "first is the smaller uuidString")
    XCTAssertEqual(kept.first?.second.id, c)
    XCTAssertEqual(kept.first?.pair, pairAuto)

    XCTAssertEqual(TransferPairWrite.writes(from: marks, readStates: states, touching: []), [])

    var missing = states
    missing[s] = nil
    XCTAssertEqual(TransferPairWrite.writes(from: marks, readStates: missing, touching: [s]), [])

    XCTAssertEqual(TransferPairWrite.writes(from: [marks[0]], readStates: states, touching: [s]), [])
  }

  /// TR5. Two writes sharing a leg are both refused. A third, independent write
  /// is the only one that lands.
  func testAcceptedDropsARowClaimedTwice() {
    let sState = TransferLegState(id: s, accountID: savingsAccount, pair: unmarked)
    let cState = TransferLegState(id: c, accountID: cardAccount, pair: unmarked)
    let x = UUID(uuidString: "D0000000-0000-0000-0000-00000000000D")!
    let xState = TransferLegState(id: x, accountID: cardAccount, pair: unmarked)
    let p = UUID(uuidString: "E0000000-0000-0000-0000-000000000001")!
    let q = UUID(uuidString: "E0000000-0000-0000-0000-000000000002")!
    let pState = TransferLegState(id: p, accountID: savingsAccount, pair: unmarked)
    let qState = TransferLegState(id: q, accountID: cardAccount, pair: unmarked)

    let first = TransferPairWrite(first: sState, second: cState, pair: pairAuto)
    let second = TransferPairWrite(first: sState, second: xState, pair: pairAuto)
    let third = TransferPairWrite(
      first: pState, second: qState,
      pair: TransferPair(groupID: UUID(uuidString: "F0000000-0000-0000-0000-000000000001"), sourceRaw: "auto"))

    let now = [s: sState, c: cState, x: xState, p: pState, q: qState]

    XCTAssertEqual(TransferPairWrite.accepted([first, second], now: now), [])
    XCTAssertEqual(TransferPairWrite.accepted([first, second, third], now: now), [third])
  }

  /// TR5. Duplicate ids resolve to the cautious account: a disputed id is a bank
  /// with no digits, never a card. Identical duplicates keep their value.
  func testByIDNeverInventsACard() {
    let id = UUID(uuidString: "AC000000-0000-0000-0000-0000000000DD")!
    let card = TransferAccount(kind: .card, lastFour: "4471")
    let bank = TransferAccount(kind: .bank, lastFour: "2210")

    XCTAssertEqual(
      TransferAccount.byID([(id, card), (id, bank)]),
      [id: TransferAccount(kind: .bank, lastFour: "")])
    XCTAssertEqual(
      TransferAccount.byID([(id, card), (id, card)]),
      [id: card])
    XCTAssertEqual(TransferAccount.byID([(id, bank)]), [id: bank])
  }
}

// MARK: - Store-backed (TR5)

/// The pair marks through `SwiftDataPipelineStore`, on a real container. XCTest,
/// and in its own class so a SwiftData trap cannot hide the pure tests above.
final class TransferDetectorStoreTests: XCTestCase {

  /// A `ModelContainer` must outlive the store that uses it (memory note on
  /// SwiftData tests). Held as a stored property.
  private var keepAlive: ModelContainer?

  private let calendar = Fixture.calendar
  private let savingsAccount = UUID(uuidString: "AC000000-0000-0000-0000-00000000000A")!
  private let cardAccount = UUID(uuidString: "AC000000-0000-0000-0000-00000000000C")!
  private let s = UUID(uuidString: "5A000000-0000-0000-0000-000000000001")!
  private let c = UUID(uuidString: "C0000000-0000-0000-0000-000000000002")!
  private let s2 = UUID(uuidString: "5A000000-0000-0000-0000-000000000004")!
  private let c2 = UUID(uuidString: "C0000000-0000-0000-0000-000000000005")!
  /// The card credit of the independent 5,000.00 pair.
  private let cSmall = UUID(uuidString: "C0000000-0000-0000-0000-00000000000E")!
  private let pairGroupSC = UUID(uuidString: "68B3C33E-3C4F-86E1-26F9-FA94A30C05B4")!

  private lazy var accounts: [UUID: TransferAccount] = [
    savingsAccount: TransferAccount(kind: .bank, lastFour: "2210"),
    cardAccount: TransferAccount(kind: .card, lastFour: "4471"),
  ]

  private let november = Fixture.date("2026-11-01 00:00")...Fixture.date("2026-11-30 23:59")

  private func makeContainer() throws -> ModelContainer {
    let schema = Schema([
      Transaction.self,
      NomiCore.Category.self,
      Budget.self,
      BudgetAlertLog.self,
      Rule.self,
      Account.self,
      AccountBinding.self,
      ColumnMappingRecord.self,
    ])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    // The accounts the detector reads: the savings bank and the card (TR1).
    let context = ModelContext(container)
    context.insert(Account(id: savingsAccount, displayName: "Savings", institution: "HDFC", lastFour: "2210", kindRaw: "bank"))
    context.insert(Account(id: cardAccount, displayName: "Card", institution: "HDFC", lastFour: "4471", kindRaw: "card"))
    try context.save()
    return container
  }

  /// A stored row for a draft on `day` of November, through the same derivation
  /// the ingest uses.
  private func stored(
    _ id: UUID, _ direction: Direction, _ narration: String, day: Int,
    amount: Int = 2_000_000, account: UUID, categoryID: UUID? = nil
  ) -> TransactionSnapshot {
    let draft = Fixture.draft(
      date: String(format: "2026-11-%02d", day),
      description: narration,
      amountMinor: amount,
      direction: direction,
      source: .email,
      externalID: id.uuidString,
      accountID: account
    )
    return Fixture.row(from: draft, id: id, categoryID: categoryID, categorySource: categoryID == nil ? .none : .manual)
  }

  private func insertFixtureF(_ store: SwiftDataPipelineStore) async throws {
    try await store.apply(CommitPlan(inserts: [
      stored(s, .debit, "HDFC CREDIT CARD PAYMENT", day: 10, account: savingsAccount),
      stored(c, .credit, "PAYMENT RECEIVED - THANK YOU", day: 11, account: cardAccount),
    ]))
  }

  /// The writes the store's own reads support for `touching`, over the given
  /// amounts. Each read leg carries the pair it was read with.
  private func decide(
    _ store: SwiftDataPipelineStore,
    amounts: [Int] = [2_000_000],
    touching: Set<UUID>
  ) async throws -> [TransferPairWrite] {
    var rows: [TransactionSnapshot] = []
    for amount in amounts {
      rows += try await store.transferCandidates(amountMinor: amount, dateRange: november)
    }
    let marks = TransferDetector.detect(rows: rows, accounts: try await store.accountFacts(), calendar: calendar)
    let states = Dictionary(uniqueKeysWithValues: rows.map {
      ($0.id, TransferLegState(id: $0.id, accountID: $0.accountID, pair: $0.transferPairAtRead))
    })
    return TransferPairWrite.writes(from: marks, readStates: states, touching: touching)
  }

  private func storedRows(_ container: ModelContainer) throws -> [UUID: Transaction] {
    let rows = try ModelContext(container).fetch(FetchDescriptor<Transaction>())
    return Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
  }

  /// Both legs of the pair land in the store, whole, with the group and `auto`.
  func testAMatchedPairLandsInTheStore() async throws {
    let container = try makeContainer()
    keepAlive = container
    let store = SwiftDataPipelineStore(modelContainer: container)
    try await insertFixtureF(store)

    let writes = try await decide(store, touching: [s, c])
    XCTAssertEqual(writes.count, 1)
    let landed = try await store.applyTransferMarks(writes, updatedAt: Fixture.commitTime)

    XCTAssertEqual(landed.count, 1)
    let rows = try storedRows(container)
    XCTAssertEqual(rows[s]?.transferGroupID, pairGroupSC)
    XCTAssertEqual(rows[s]?.transferSourceRaw, "auto")
    XCTAssertEqual(rows[c]?.transferGroupID, pairGroupSC)
    XCTAssertEqual(rows[c]?.transferSourceRaw, "auto")
  }

  /// A second run over the stored rows finds nothing to write.
  func testASecondRunOverTheStoreWritesNothing() async throws {
    let container = try makeContainer()
    keepAlive = container
    let store = SwiftDataPipelineStore(modelContainer: container)
    try await insertFixtureF(store)
    _ = try await store.applyTransferMarks(try await decide(store, touching: [s, c]), updatedAt: Fixture.commitTime)

    let again = try await decide(store, touching: [s, c])

    XCTAssertEqual(again, [])
  }

  /// A write built from legs the store did not read carries no read pair, so
  /// nothing lands (Amendment 3, fails closed). Both rows stay unmarked.
  func testAWriteNotReadFromTheStoreNeverLands() async throws {
    let container = try makeContainer()
    keepAlive = container
    let store = SwiftDataPipelineStore(modelContainer: container)
    try await insertFixtureF(store)
    let writes = try await decide(store, touching: [s, c])
    let unread = writes.map { write in
      TransferPairWrite(
        first: TransferLegState(id: write.first.id, accountID: write.first.accountID, pair: nil),
        second: TransferLegState(id: write.second.id, accountID: write.second.accountID, pair: nil),
        pair: write.pair)
    }

    let landed = try await store.applyTransferMarks(unread, updatedAt: Fixture.commitTime)

    XCTAssertEqual(landed, [])
    let rows = try storedRows(container)
    XCTAssertNil(rows[s]?.transferSourceRaw)
    XCTAssertNil(rows[c]?.transferSourceRaw)
  }

  /// After the read, one change in another context refuses one leg. The whole
  /// pair is refused: the partner is not marked alone, and the user's leg is
  /// left as the user set it. Four changes, each in a fresh container.
  func testARefusedLegLeavesItsPartnerUnmarked() async throws {
    let otherGroup = UUID(uuidString: "00000000-0000-0000-0000-00000000000F")!
    let changes: [(String, (ModelContext) throws -> Void)] = [
      ("credit rejected", { context in
        let target = self.c
        let row = try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == target })).first
        row?.transferGroupID = nil
        row?.transferSourceRaw = TransferSource.rejected.rawValue
      }),
      ("credit marked manually", { context in
        let target = self.c
        let row = try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == target })).first
        row?.transferGroupID = otherGroup
        row?.transferSourceRaw = TransferSource.manual.rawValue
      }),
      ("credit deleted", { context in
        let target = self.c
        let row = try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == target })).first
        if let row { context.delete(row) }
      }),
      ("debit's account cleared", { context in
        let target = self.s
        let row = try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == target })).first
        row?.accountID = nil
      }),
    ]

    for (label, change) in changes {
      let container = try makeContainer()
      keepAlive = container
      let store = SwiftDataPipelineStore(modelContainer: container)
      try await insertFixtureF(store)
      let writes = try await decide(store, touching: [s, c])
      XCTAssertEqual(writes.count, 1, label)

      let context = ModelContext(container)
      try change(context)
      try context.save()

      let landed = try await store.applyTransferMarks(writes, updatedAt: Fixture.date("2026-11-20 09:00"))

      XCTAssertEqual(landed, [], label)
      let rows = try storedRows(container)
      XCTAssertNil(rows[s]?.transferSourceRaw, "\(label): debit must stay unmarked")
      XCTAssertNil(rows[s]?.transferGroupID, label)
      XCTAssertEqual(rows[s]?.updatedAt, Fixture.date("2026-08-20 10:00"), "\(label): debit's updatedAt must not move")
      if label == "credit deleted" {
        XCTAssertNil(rows[c], label)
      } else if label == "debit's account cleared" {
        XCTAssertNil(rows[s]?.accountID, label)
      } else if label == "credit rejected" {
        XCTAssertEqual(rows[c]?.transferSourceRaw, TransferSource.rejected.rawValue, label)
        XCTAssertNil(rows[c]?.transferGroupID, label)
      } else {
        XCTAssertEqual(rows[c]?.transferGroupID, otherGroup, label)
        XCTAssertEqual(rows[c]?.transferSourceRaw, TransferSource.manual.rawValue, label)
      }
    }
  }

  /// One refused pair does not block an independent pair in the same call. Fixture
  /// F's credit is rejected after the read; a 5,000.00 pair is untouched by that.
  func testOneRefusedPairDoesNotBlockAnother() async throws {
    let container = try makeContainer()
    keepAlive = container
    let store = SwiftDataPipelineStore(modelContainer: container)
    try await insertFixtureF(store)
    try await store.apply(CommitPlan(inserts: [
      stored(s2, .debit, "CC PAYMENT 4471", day: 10, amount: 500_000, account: savingsAccount),
      stored(cSmall, .credit, "PAYMENT RECEIVED", day: 11, amount: 500_000, account: cardAccount),
    ]))
    let writes = try await decide(store, amounts: [2_000_000, 500_000], touching: [s, c, s2])
    XCTAssertEqual(writes.count, 2)

    let context = ModelContext(container)
    let target = c
    let credit = try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == target })).first
    credit?.transferGroupID = nil
    credit?.transferSourceRaw = TransferSource.rejected.rawValue
    try context.save()

    let landed = try await store.applyTransferMarks(writes, updatedAt: Fixture.commitTime)

    XCTAssertEqual(landed.count, 1)
    let pairLanded = try XCTUnwrap(landed.first)
    XCTAssertEqual(Set([pairLanded.first.id, pairLanded.second.id]), [s2, cSmall])
    let rows = try storedRows(container)
    XCTAssertEqual(rows[s2]?.transferSourceRaw, "auto")
    XCTAssertEqual(rows[cSmall]?.transferSourceRaw, "auto")
    XCTAssertNil(rows[s]?.transferSourceRaw, "the refused pair stays unmarked")
    XCTAssertEqual(rows[c]?.transferSourceRaw, TransferSource.rejected.rawValue)
  }

  /// A pair is written onto its two legs and nothing else. The user's category
  /// on a leg, set after the read, is still there after the mark.
  func testAMarkWritesOnlyThePair() async throws {
    let container = try makeContainer()
    keepAlive = container
    let store = SwiftDataPipelineStore(modelContainer: container)
    try await insertFixtureF(store)
    let writes = try await decide(store, touching: [s, c])
    let userCategory = UUID(uuidString: "CA000000-0000-0000-0000-000000000001")!

    let context = ModelContext(container)
    let target = s
    let debit = try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == target })).first
    debit?.categoryID = userCategory
    debit?.categorySourceRaw = CategorySource.manual.rawValue
    try context.save()

    _ = try await store.applyTransferMarks(writes, updatedAt: Fixture.commitTime)

    let rows = try storedRows(container)
    XCTAssertEqual(rows[s]?.categoryID, userCategory)
    XCTAssertEqual(rows[s]?.transferSourceRaw, "auto")
    XCTAssertEqual(rows[s]?.transferGroupID, pairGroupSC)
  }
}

// MARK: - Pipeline (TR5)

/// The detector wired into `IngestPipeline`, over `FakePipelineStore`, which
/// follows the real store's rules. Calendar is `Fixture.calendar` throughout.
final class TransferDetectorPipelineTests: XCTestCase {

  private let savingsAccount = UUID(uuidString: "AC000000-0000-0000-0000-00000000000A")!
  private let cardAccount = UUID(uuidString: "AC000000-0000-0000-0000-00000000000C")!
  private var accounts: [UUID: TransferAccount] {
    [
      savingsAccount: TransferAccount(kind: .bank, lastFour: "2210"),
      cardAccount: TransferAccount(kind: .card, lastFour: "4471"),
    ]
  }

  private func debitDraft(_ id: String = "S", day: String = "2026-11-10") -> TransactionDraft {
    Fixture.draft(date: day, description: "HDFC CREDIT CARD PAYMENT", amountMinor: 2_000_000,
                  direction: .debit, source: .email, externalID: "uid-\(id)", accountID: savingsAccount)
  }

  private func creditDraft(_ id: String = "C", day: String = "2026-11-11") -> TransactionDraft {
    Fixture.draft(date: day, description: "PAYMENT RECEIVED - THANK YOU", amountMinor: 2_000_000,
                  direction: .credit, source: .email, externalID: "uid-\(id)", accountID: cardAccount)
  }

  private func row(_ rows: [TransactionSnapshot], _ direction: Direction) -> TransactionSnapshot? {
    rows.first { $0.directionRaw == direction.rawValue && $0.amountMinor == 2_000_000 }
  }

  /// Both legs arrive in one batch. Both are marked, with one shared group made
  /// from their ids, and the observer is called once for the batch.
  func testIngestMarksAPairArrivingInOneBatch() async throws {
    let store = FakePipelineStore(accounts: accounts)
    let observer = RecordingObserver()
    let pipeline = await Fixture.pipeline(store: store, observer: observer)

    try await pipeline.ingest([debitDraft(), creditDraft()])

    let all = await store.allRows
    let debit = try XCTUnwrap(row(all, .debit))
    let credit = try XCTUnwrap(row(all, .credit))
    XCTAssertEqual(debit.transferSourceRaw, "auto")
    XCTAssertEqual(credit.transferSourceRaw, "auto")
    XCTAssertEqual(debit.transferGroupID, TransferGroupID.make(debit.id, credit.id))
    XCTAssertEqual(credit.transferGroupID, debit.transferGroupID)
    XCTAssertEqual(observer.callCount, 1)
  }

  /// A leg already stored is marked by the leg that arrives later.
  func testIngestMarksAgainstAStoredLeg() async throws {
    let stored = Fixture.row(from: debitDraft())
    let store = FakePipelineStore(rows: [stored], accounts: accounts)
    let pipeline = await Fixture.pipeline(store: store)

    try await pipeline.ingest([creditDraft()])

    let storedDebit = await store.row(stored.id)
    let all = await store.allRows
    let debit = try XCTUnwrap(storedDebit)
    let credit = try XCTUnwrap(row(all, .credit))
    XCTAssertEqual(debit.transferSourceRaw, "auto")
    XCTAssertEqual(credit.transferSourceRaw, "auto")
    XCTAssertEqual(debit.transferGroupID, TransferGroupID.make(debit.id, credit.id))
  }

  /// A pair stored unmarked is not written by an ingest that does not touch it.
  /// The detector finds the pair, but none of its legs is a seed of this batch,
  /// so `applyTransferMarks` is never called.
  func testIngestLeavesAPairWithNoTouchedLegAlone() async throws {
    let debit = Fixture.row(from: debitDraft())
    let credit = Fixture.row(from: creditDraft())
    let store = FakePipelineStore(rows: [debit, credit], accounts: accounts)
    let pipeline = await Fixture.pipeline(store: store)

    // An Amazon debit on the card: same amount, same account as the credit, so it
    // matches neither leg.
    try await pipeline.ingest([Fixture.draft(
      date: "2026-11-11", description: "AMAZON", amountMinor: 2_000_000, direction: .debit,
      source: .email, externalID: "uid-amazon", accountID: cardAccount)])

    let writes = await store.appliedTransferWrites
    let debitNow = await store.row(debit.id)
    let creditNow = await store.row(credit.id)
    XCTAssertEqual(writes, [])
    XCTAssertNil(debitNow?.transferSourceRaw)
    XCTAssertNil(creditNow?.transferSourceRaw)
  }

  /// The read reaches a partner's own competitors. The credit is ingested on
  /// 10 Nov; a stored debit on 13 Nov could pair with it, but a second stored
  /// credit on 16 Nov makes the debit ambiguous. The read must see the 16 Nov row
  /// (six days from the seed) to refuse the mark.
  func testTheReadReachesThePartnersOtherCandidates() async throws {
    let debit = Fixture.row(from: debitDraft("D", day: "2026-11-13"))
    let otherCredit = Fixture.row(from: creditDraft("C2", day: "2026-11-16"))
    let store = FakePipelineStore(rows: [debit, otherCredit], accounts: accounts)
    let pipeline = await Fixture.pipeline(store: store)

    try await pipeline.ingest([creditDraft("C", day: "2026-11-10")])

    let writes = await store.appliedTransferWrites
    let debitNow = await store.row(debit.id)
    let otherNow = await store.row(otherCredit.id)
    XCTAssertEqual(writes, [])
    XCTAssertNil(debitNow?.transferSourceRaw)
    XCTAssertNil(otherNow?.transferSourceRaw)
  }

  /// A detection failure is absorbed. The ingest returns normally, the rows are
  /// stored and counted, nothing is marked, and the observer still hears the batch.
  func testADetectionFailureDoesNotFailTheIngest() async throws {
    let store = FakePipelineStore(accounts: accounts)
    await store.setFailAccountFacts(true)
    let observer = RecordingObserver()
    let pipeline = await Fixture.pipeline(store: store, observer: observer)

    let result = try await pipeline.ingest([debitDraft(), creditDraft()])

    let rowCount = await store.rowCount
    let writes = await store.appliedTransferWrites
    XCTAssertEqual(result.created, 2)
    XCTAssertEqual(rowCount, 2)
    XCTAssertEqual(writes, [])
    XCTAssertEqual(observer.callCount, 1)
  }
}
