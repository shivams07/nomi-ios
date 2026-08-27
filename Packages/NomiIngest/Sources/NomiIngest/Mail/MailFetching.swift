import Foundation
import NomiCore

/// State of a selected mailbox, from `SELECT`.
public struct MailboxState: Sendable, Equatable {
  public let name: String
  /// When this changes, every stored UID is meaningless and the mailbox must be
  /// rescanned. `MailMessage.externalID` carries it for exactly that reason.
  public let uidValidity: UInt32
  public let uidNext: UInt32

  public init(name: String, uidValidity: UInt32, uidNext: UInt32) {
    self.name = name
    self.uidValidity = uidValidity
    self.uidNext = uidNext
  }
}

/// The transport seam. Everything above it is deterministic and tested; below it
/// is a network protocol against a server no one on this team can reach.
///
/// The split is the same one U4 made with `PipelineStore`, and for the same
/// reason: on this project CI is the only machine that has ever compiled a line
/// (R1), and nothing that needs a live IMAP server can be verified at all. So
/// every decision — what to fetch, what is a candidate, which layer read it,
/// what the summary says — sits on this side of the protocol and is covered by
/// fixtures.
///
/// **Implementations must use `FETCH BODY.PEEK[]`, never `FETCH BODY[]`** (R4).
/// `BODY[]` sets `\Seen` on the user's real mail while merely scanning it: a
/// visible, annoying, hard-to-undo regression in a mailbox this app does not
/// own. It is not a detail.
public protocol MailFetching: Sendable {
  func connect(_ credentials: IMAPCredentials) async throws
  func disconnect() async throws

  /// `SELECT` (or `EXAMINE`, which is better here — read-only by construction).
  func selectMailbox(_ name: String) async throws -> MailboxState

  /// `UID SEARCH SINCE <date>`. Used by the 6-month backfill.
  func uids(since date: Date, in mailbox: String) async throws -> [UInt32]

  /// `UID SEARCH UID <uid+1>:*`. Used by incremental sync.
  func uids(after uid: UInt32, in mailbox: String) async throws -> [UInt32]

  /// `UID FETCH <set> (BODY.PEEK[])`, parsed through `RFC822Message`.
  ///
  /// **Must throw if the server hangs up before the tagged completion** — an
  /// unexpected `* BYE`, a closed socket, a truncated literal. Returning the
  /// messages that happened to arrive would make a hangup indistinguishable from
  /// "0 new transactions", which is the silent-zero failure this whole layer is
  /// arranged to avoid (§2.16).
  ///
  /// Throwing is safe and cheap: `MailSyncEngine` advances its cursor only after
  /// a fetch AND an ingest both succeed, so the same UIDs are simply re-fetched
  /// next sync, and re-ingesting a `SourceRef` the pipeline already holds is a
  /// total no-op. Asserted in `MailSyncEngineTests`.
  func fetch(uids: [UInt32], in mailbox: String) async throws -> [MailMessage]
}

/// Where the incremental sync left off. Persisted by U8; U2 only reads and
/// returns it.
public struct MailSyncCursor: Sendable, Equatable, Codable {
  public let mailbox: String
  public let uidValidity: UInt32
  public let lastSeenUID: UInt32

  public init(mailbox: String, uidValidity: UInt32, lastSeenUID: UInt32) {
    self.mailbox = mailbox
    self.uidValidity = uidValidity
    self.lastSeenUID = lastSeenUID
  }
}

/// The pipeline, behind a protocol so `MailSyncEngine` can be tested without a
/// `ModelContext`. `IngestPipeline` is an actor and satisfies this as-is.
public protocol DraftIngesting: Sendable {
  func ingest(_ drafts: [TransactionDraft]) async throws -> IngestBatchResult
}

extension IngestPipeline: DraftIngesting {}
