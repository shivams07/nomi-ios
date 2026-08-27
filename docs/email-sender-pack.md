# The email sender pack

How Nomi turns a bank alert email into a transaction, and how to fix it when a
bank changes its format.

Design references: §1.4 (two layers plus a pre-filter), §1.5 (the extractor
seam), §2.5.1 and §2.5.2 (why the bank list is discovered rather than supplied),
R4 (IMAP), R6 and R19 (why green CI here does not mean the amounts are right).

---

## The pack is PROVISIONAL

`senders.json` ships entries for **SBI, HDFC, ICICI, Axis and Kotak**.

**These are defaults. They are not a claim about which banks anyone actually
uses.** Nobody was asked which banks they bank with, and nobody read anyone's
mail to work it out — §2.5.1 sets out why both routes were rejected, and §2.5.2
records that the decision was reversed and why it changes nothing here: no agent
on this team has mailbox access, and the IMAP client that would grant it is this
unit's own deliverable.

If three of the five are wrong, the app still works. Those senders fall through
to the Layer-2 heuristic extractor, every row they produce is flagged
`needsReview`, and their domains are reported back through
`SyncSummary.unmatchedSenders`. **The app produces the real bank list on the
user's own device, at first backfill.**

Correcting an entry is a data edit to one file. No code change, no unit, no
re-plan.

---

## The three stages

### 1. The pre-filter — a hard gate

A message is a transaction candidate only if **all three** hold:

| Check | Where | Rejection |
|---|---|---|
| Sender domain is bank-ish | `MailPreFilter.isCandidateDomain` | `.unknownDomain` |
| Body carries a currency amount (`₹`, `INR`, `Rs.`, `Rs `) | `MailAmount` | `.noCurrencyAmount` |
| Body carries a transaction verb | `MailDirection.candidateVerbs` | `.noTransactionVerb` |

This is what makes "an email that is not a transaction produces no transaction"
true. A bank promo reading *"Get ₹500 cashback"* has the domain and the amount
and fails on the verb. A promo from a domain nobody recognises never reaches an
extractor at all.

**The domain gate is deliberately wider than the pack**, in three rings:

1. a pack entry (matched as a domain suffix, so `alerts.hdfcbank.net` hits the
   `hdfcbank.net` entry — banks add and drop alert subdomains without notice)
2. `candidateDomains` — exact domains with no pack entry yet
3. `candidateDomainTokens` — any domain containing `bank`, `card`, `upi`, …

If the gate were only the pack, Layer 2 could never run and `unmatchedSenders`
would always be empty. The pack cannot be both the precision list and the
admission list.

**`credit` on its own is not an admission verb.** Every promotional mail in India
says "Credit Card"; admitting on bare `credit` would switch the gate off. The
gate takes the strong forms (`debited`, `credited`, `spent`, …) plus two
unambiguous phrasings — `has a debit`, `debit by` — which is what lets SBI's
"has a debit by transfer of Rs 3,000.00" through without letting a card offer in
beside it. Once a message is *already* a candidate, bare `debit` / `credit` is
used to resolve direction.

### 2. Layer 1 — the declarative pack (precision)

A pack entry is `{ senderDomain, bankLabel, subjectPattern, fieldRegexes,
accountHint }`. Capture group 1 of each regex is the value.

| Field | Required | Meaning |
|---|---|---|
| `amount` | **yes** | the transaction amount. No match ⇒ Layer 1 declines the whole message |
| `date` | no | falls back to the first parseable date in the body, then the `Date:` header |
| `direction` | no | falls back to the first verb in the body |
| `accountFragment` | no | last four of the account or card; feeds `AccountBindingResolving` |
| `narration` | no | the raw narration for `descriptionText` |

Amount being required is the point: a partial Layer-1 match is dropped to Layer 2
rather than half-used. Precision over recall is the whole reason there are two
layers instead of one lenient one.

### 3. Layer 2 — the generic heuristic (recall, gated)

For candidates that match no pack entry: the **largest** currency amount, the
first parseable date, the direction from the verb, the merchant from narration
heuristics.

Largest-wins is a heuristic and it is wrong sometimes — a mail quoting both the
charge and the running balance yields the balance. **Every Layer-2 row is created
`needsReview = true`**, and the review queue shows the raw source. Recall with a
human gate.

A candidate that no layer can read produces **one** flagged row with
`amountMinor = 0`, not a guess and not a silent miss. A wrong number that looks
right is the worst failure available here (R6).

---

## Adding or fixing a bank

1. Open `Packages/NomiIngest/Sources/NomiIngest/Resources/SendersPackJSON.swift`.
2. Add an entry, or edit the regexes on an existing one.
3. Add **at least two** `.eml` fixtures under
   `Packages/NomiIngest/Tests/NomiIngestTests/Fixtures/Mail/` and an expectation
   row in `MailExtractionFixtureTests`.

That is the whole change. No Swift outside the JSON literal moves.

### Why the pack is a Swift file and not `senders.json`

The design specifies `Resources/senders.json`, loaded as a bundled resource. That
cannot be done as the repo stands: **U0 froze `NomiIngest/Package.swift` with no
`resources:` declaration**, so SwiftPM never synthesises `Bundle.module` and a
bundled JSON file is unreachable at runtime.

Editing a frozen manifest was not this unit's call to make, and it is not free
either — the same target is built by U3's `File/`, U4's `Pipeline/` and U8's app,
so a mistake there breaks three other branches. The pack therefore ships as JSON
held in a Swift raw-string literal, in the directory the design assigns it,
decoded through exactly the `Codable` path a bundled file would use.

To make it a real resource later, the entire change is:

1. move the literal into `Resources/senders.json`
2. add `resources: [.process("Resources")]` to the `NomiIngest` target
3. in `SenderPack.bundled`, swap `SendersPackJSON.raw.data(using:)` for
   `Bundle.module.url(forResource: "senders", withExtension: "json")`

Nothing else moves. §1.4's CloudKit-hosted pack, when it arrives, slots into the
same place.

---

## Dropping real `.eml` samples in

The fixtures are **real RFC 5322 messages**, parsed by the same
`RFC822Message` the IMAP transport uses on a `FETCH BODY.PEEK[]` payload. There
is no adapter in between.

So: save a bank alert from a mail client as `.eml`, drop it in
`Tests/NomiIngestTests/Fixtures/Mail/`, add an expectation row, done. It exercises
the production path exactly. That is the form §2.5.2's instruction can actually
take, and it is a test-only follow-up against files this unit already owns — not
a redo.

**Real samples are worth more than a list of bank names.** A correct bank list
changes at most five JSON strings. Real samples fix the list *and* test the
nested-table HTML that R6 says is the actual risk.

---

## What the fixtures do and do not prove

**They are structural.** Built from publicly documented alert formats, not
harvested from anyone's mailbox.

A green CI run here means **the parser is structurally correct**. It does **not**
mean the amounts are right on real bank mail. R6: Indian bank mail is
nested-table HTML with amounts split across cells, and a hand-built fixture
reproduces the format but not the mess. **The first real backfill is the actual
test.**

Two fixtures do attack R6 head-on, because it is the failure a synthetic fixture
is most likely to omit:

- `hdfc_debit_split_cells.eml` — currency symbol, rupees and paise each in their
  own `<td>`
- `icici_debit_nested_split.eml` — nested tables, paise in a cell that opens with
  the decimal point

`MailHTML.rejoinSplitDecimals` is the one rule that handles all three split
shapes. It is deliberately narrow: it requires a literal decimal point and a bare
two-digit fraction, so it cannot glue two adjacent whole amounts in a statement
table into one wrong number.

---

## Determinism (§1.5)

`TransactionExtractor.extract` feeds `dedupeKey`, so identical input bytes must
produce identical output on every device, forever.

The one place that took a decision rather than falling out for free: **body dates
are parsed in a fixed `Asia/Kolkata`, never `TimeZone.current`.** A body date like
`27-08-2026` carries no zone; parsing it in the device zone would give two of the
user's devices two different instants for one email, two different `dedupeKey`s,
and two rows the reconcile pass cannot collapse. India is the whole target market
and Indian alerts are IST-stamped, so IST is both the deterministic choice and
the correct one. Locale is pinned to `en_US_POSIX` for the same reason.

Date formats are chosen by the **shape** of the matched text, not tried blind in
order — blind iteration is how `2026-08-13` gets read as `dd-MM-yyyy` and yields
a date in the year 13.

---

## No Foundation Models, and the seam that keeps it that way

There is no `import FoundationModels` in this codebase and there must not be at
MVP (§1.5, R12).

Extraction sits behind **two** protocols, not one:

- `TransactionExtractor` — canonical, deterministic, feeds `dedupeKey`
- `ExtractionEnricher` — optional, best-effort, may only suggest fields that do
  **not** feed `dedupeKey`

At MVP there is exactly one `TransactionExtractor` and **zero**
`ExtractionEnricher` implementations. An FM implementation could only ever be an
enricher, so it is structurally incapable of touching `date`, `amountMinor` or
`normalizedDescription`. The rule is in the type system, not in a review
checklist.

`SyncSummary.packMatched` and `heuristicMatched` are the measurement the whole
question turns on. After a real backfill: a small heuristic share means Layer 1
covers the user's banks and FM is never worth its cost; a large share means the
tail is where the data lives.

---

## What this unit does NOT parse

**UPI narrations.** `descriptionText` carries the raw narration verbatim and
U4's pipeline derives `merchantName`, `upiKindRaw` and `counterpartyVPA` from it
(§2.4). An ingester that fills those in trips the pipeline's assert. No test in
this unit asserts on `merchantName`, because it is not this unit's output.

The narration preference order is: a UPI/NEFT reference, then the pack's
`narration` regex, then a merchant heuristic, then the clause around the amount.
The reference outranks the pack's merchant capture on purpose — a net-banking CSV
for the same transaction carries `UPI-SWIGGY-swiggy@ybl-622104477311`, and
`SWIGGY` alone will not reach the 0.9 similarity the near-match dedupe tier
needs. Prettiness loses to the join.

---

## The transport, and what is missing

Everything above reads a `MailMessage`. Getting one off a server is
`MailFetching`, and **this unit ships the seam, the sync engine that drives it,
and no IMAP implementation.** See the PR for the escalation; the short version is
R4's instruction to timebox the `swift-nio-imap` route rather than grind, taken
in a week where CI cannot compile anything.

Whatever implements `MailFetching` must:

- connect over **TLS on 993**, authenticating with an app-specific password read
  from `KeychainCredentialStore` (§1.1)
- `EXAMINE` rather than `SELECT` where possible — read-only by construction
- **`UID FETCH … (BODY.PEEK[])`, never `BODY[]`** (R4). `BODY[]` sets `\Seen` on
  the user's real mail while merely scanning it: a visible, annoying,
  hard-to-undo regression in a mailbox this app does not own
- carry `UIDVALIDITY` out of `SELECT`, so `MailSyncEngine` can tell a normal
  incremental sync from a mailbox rebuild
- hand raw message bytes to `RFC822Message.parse` and nothing else

`MailSyncEngine` already handles the rest: incremental `UID SEARCH` above the
cursor, the six-month backfill, the UIDVALIDITY rescan, and the counters.
