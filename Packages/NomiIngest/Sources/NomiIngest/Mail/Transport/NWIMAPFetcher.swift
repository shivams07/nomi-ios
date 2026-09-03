import Foundation
import Network
import NomiCore

// MARK: - The byte channel

/// The socket, behind a protocol.
///
/// **This is the line between what CI can execute and what only a real mailbox
/// can.** Everything above it — command sequencing, tag matching, `* BYE`
/// before a tagged completion, literal reassembly across packet boundaries,
/// EXAMINE and SEARCH parsing — is driven by `NWIMAPFetcher` and is covered by
/// tests against a scripted channel. Everything below it is `NWConnection`, and
/// no test on this project can reach a live IMAP server.
///
/// Same split U4 made with `PipelineStore` and U2 made with `MailFetching`, for
/// the same stated reason: CI is the only machine that has ever compiled a line
/// of this project, so every decision belongs on the side a test can run.
public protocol IMAPByteChannel: Sendable {
  func open(host: String, port: Int) async throws
  func send(_ bytes: [UInt8]) async throws
  /// One chunk, however the network delivered it. **Never assume a chunk is a
  /// line or a response** — the read path above this is built to survive
  /// arbitrary splits, and the tests feed it one byte at a time to prove it.
  ///
  /// Throws `IMAPTransportError.connectionClosed` at EOF.
  func receive() async throws -> [UInt8]
  func close() async
}

/// The real socket: `NWConnection` with `.tls` over TCP.
///
/// **Compile-verified only against a real server.** Nothing in this project's CI
/// opens a TLS connection to an IMAP host. `NWIMAPFetcherTests` exercises the
/// failure paths that *are* reachable from a test — a TLS handshake against a
/// plain-TCP listener, and a refused connection — and the rest is named as
/// unverified in this unit's PR rather than implied by a green run.
///
/// Network.framework is a system framework: no manifest edit, §2.10's freeze
/// untouched. `NIOSSL`, `NIOTransportServices` and `NIOPosix` were all rejected.
public final class NWConnectionChannel: IMAPByteChannel, @unchecked Sendable {
  /// Every network call gets one. A socket that is open but silent is the
  /// failure with no natural end: without a deadline a sync neither completes
  /// nor fails and the UI sits on `.connecting` forever.
  ///
  /// `TimeInterval` rather than `Duration` so these drop straight into
  /// `DispatchQueue.asyncAfter` with no conversion — the timer runs on the
  /// connection's own queue, beside the callbacks it has to race.
  public struct Timeouts: Sendable {
    public var connect: TimeInterval
    public var read: TimeInterval
    public var write: TimeInterval

    public init(connect: TimeInterval = 30, read: TimeInterval = 60, write: TimeInterval = 30) {
      self.connect = connect
      self.read = read
      self.write = write
    }
  }

  private let timeouts: Timeouts
  private let queue = DispatchQueue(label: "ai.nomi.imap.connection")
  private let lock = NSLock()
  private var connection: NWConnection?

  public init(timeouts: Timeouts = Timeouts()) {
    self.timeouts = timeouts
  }

  public func open(host: String, port: Int) async throws {
    await close()

    guard port > 0, port <= Int(UInt16.max), let endpointPort = NWEndpoint.Port(rawValue: UInt16(port))
    else {
      throw IMAPTransportError.malformedResponse("invalid port \(port)")
    }

    // `.tls` on default TCP options. IMAPS is TLS from the first byte; there is
    // no STARTTLS here and there must not be. A STARTTLS flow that continues in
    // the clear when the upgrade fails is the classic downgrade, and implicit
    // TLS cannot express that mistake.
    let connection = NWConnection(
      host: NWEndpoint.Host(host),
      port: endpointPort,
      using: NWParameters(tls: .init(), tcp: .init())
    )
    setConnection(connection)

    do {
      try await perform(timeout: timeouts.connect) {
        (finish: @escaping @Sendable (Result<Void, Error>) -> Void) in
        // This handler is installed for the LIFE of the connection, not just for
        // the handshake: `finish` is one-shot behind a `ResumeGuard`, but the
        // callbacks keep arriving. So `.failed` and `.cancelled` after `.ready`
        // land here too, and until now they were dropped on the floor.
        //
        // Dropping them costs a whole read timeout. Network.framework knows the
        // socket is gone the moment it is gone; without this, the next `receive`
        // sits on it for the full 60 seconds to learn the same thing, and the
        // sync the user is waiting on hangs for a minute before failing.
        //
        // `connection` is captured weakly. A handler installed ON the connection
        // that also holds it strongly is a retain cycle broken only by `close()`
        // or `forget(_:)`, and neither is guaranteed to run.
        connection.stateUpdateHandler = { [weak self, weak connection] state in
          switch state {
          case .ready:
            finish(.success(()))
          case .failed(let error):
            if let connection { self?.forget(connection) }
            finish(.failure(error))
          case .waiting(let error):
            // `.waiting` is NWConnection saying "no route, I will retry when
            // conditions change". For a foreground sync that is a failure the
            // user should see now, not a retry loop behind a spinner — and
            // failing here gives the real reason rather than a timeout.
            finish(.failure(error))
          case .cancelled:
            if let connection { self?.forget(connection) }
            finish(.failure(IMAPTransportError.connectionClosed))
          case .setup, .preparing:
            break
          @unknown default:
            break
          }
        }
        connection.start(queue: self.queue)
      }
    } catch {
      // A connect that failed for any reason leaves nothing behind to write
      // to. The state handler covers `.failed` and `.cancelled` but not
      // `.waiting`, and not the deadline — and which of the three a refused
      // connection reports is the OS's business rather than ours. Dropping it
      // here makes "open threw" and "there is no connection" the same
      // statement, whichever path got there.
      forget(connection)
      throw error
    }
  }

  public func send(_ bytes: [UInt8]) async throws {
    let connection = try requireConnection()
    try await perform(timeout: timeouts.write) {
      (finish: @escaping @Sendable (Result<Void, Error>) -> Void) in
      connection.send(
        content: Data(bytes),
        completion: .contentProcessed { error in
          if let error {
            finish(.failure(error))
          } else {
            finish(.success(()))
          }
        }
      )
    }
  }

  public func receive() async throws -> [UInt8] {
    let connection = try requireConnection()
    return try await perform(timeout: timeouts.read) {
      (finish: @escaping @Sendable (Result<[UInt8], Error>) -> Void) in
      // `minimumIncompleteLength: 1` — take whatever arrived. Asking for more
      // would block until the peer happened to send it, and at this layer there
      // is no framing to predict a length from.
      connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
        data, _, _, error in
        if let error {
          finish(.failure(error))
        } else if let data, !data.isEmpty {
          finish(.success([UInt8](data)))
        } else {
          // No bytes: EOF. Returning an empty chunk instead would spin the
          // caller's read loop against a closed socket.
          finish(.failure(IMAPTransportError.connectionClosed))
        }
      }
    }
  }

  public func close() async {
    // The lock is taken in a synchronous helper, not here: calling
    // `NSLock.lock()` directly in an async function is a warning today and an
    // error in the Swift 6 language mode, because a suspension while holding a
    // non-async lock is a deadlock waiting to happen. Nothing suspends inside
    // `takeConnection`, which is what makes it safe.
    let existing = takeConnection()
    existing?.stateUpdateHandler = nil
    existing?.cancel()
  }

  /// Drops `dead` if it is still the current connection, so the next `send` or
  /// `receive` throws `notConnected` at once instead of waiting out a timeout.
  ///
  /// Identity-checked: `open()` cancels the old connection before starting a new
  /// one, so a late `.cancelled` for the previous socket must not take the
  /// replacement down with it.
  private func forget(_ dead: NWConnection) {
    lock.lock()
    let isCurrent = connection === dead
    if isCurrent { connection = nil }
    lock.unlock()

    guard isCurrent else { return }
    dead.stateUpdateHandler = nil
    dead.cancel()
  }

  private func takeConnection() -> NWConnection? {
    lock.lock()
    defer { lock.unlock() }
    let existing = connection
    connection = nil
    return existing
  }

  // MARK: -

  private func requireConnection() throws -> NWConnection {
    lock.lock()
    defer { lock.unlock() }
    guard let connection else { throw IMAPTransportError.notConnected }
    return connection
  }

  private func setConnection(_ new: NWConnection) {
    lock.lock()
    connection = new
    lock.unlock()
  }

  /// Bridges one Network.framework callback to `async`, with a deadline.
  ///
  /// Two things here are load-bearing rather than ceremony:
  ///
  /// - **`ResumeGuard`.** `stateUpdateHandler` fires repeatedly and a
  ///   `CheckedContinuation` may be resumed exactly once; resuming twice is a
  ///   crash, not an error. Cancelling on timeout makes a second callback
  ///   *ordinary* rather than exotic, so this is not defensive.
  /// - **Cancelling the connection when the timer wins.** Abandoning the
  ///   `await` alone would leave the underlying callback pending forever and
  ///   leak the connection. The cancel forces it to complete, and the guard
  ///   absorbs whichever arrives second.
  /// The completion is `@Sendable` because Network.framework's callbacks are:
  /// `stateUpdateHandler`, `send(completion:)` and `receive` all take
  /// `@Sendable` closures, so anything they capture has to be too.
  private func perform<T>(
    timeout: TimeInterval,
    _ body: (@escaping @Sendable (Result<T, Error>) -> Void) -> Void
  ) async throws -> T {
    let resumeGuard = ResumeGuard()
    return try await withCheckedThrowingContinuation { continuation in
      let timer = DispatchWorkItem { [weak self] in
        guard resumeGuard.claim() else { return }
        Task { await self?.close() }
        continuation.resume(throwing: IMAPTransportError.connectionClosed)
      }
      queue.asyncAfter(deadline: .now() + timeout, execute: timer)

      body { result in
        guard resumeGuard.claim() else { return }
        timer.cancel()
        continuation.resume(with: result)
      }
    }
  }
}

/// One-shot claim, so a `CheckedContinuation` is resumed exactly once no matter
/// how many times a Network.framework handler fires.
private final class ResumeGuard: @unchecked Sendable {
  private let lock = NSLock()
  private var claimed = false

  func claim() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    if claimed { return false }
    claimed = true
    return true
  }
}

// MARK: - The fetcher

/// `MailFetching` over a real IMAP connection — U2b's deliverable (1),
/// finished.
///
/// **An actor with an explicit mutex, and the mutex is the point.** Swift actors
/// are *reentrant*. Every command here is send-then-read-until-tagged, which
/// suspends several times, so without a held lock a second call can begin
/// mid-command and interleave two commands' bytes on one socket — handing one
/// command's response to the other's parser. `IngestPipeline` failed on CI for
/// exactly this and fixed it exactly this way; this is a known bug being
/// designed out, not a precaution.
///
/// **The transport answers one command at a time and decides nothing.** It does
/// not window searches, batch fetches, or re-chunk what it is handed — the
/// engine owns all of that (§2.17), and a transport that read ahead would put
/// back the memory ceiling the batching exists to hold.
public actor NWIMAPFetcher: MailFetching {
  private let channel: any IMAPByteChannel
  private let reader: any IMAPResponseReading

  private var tags = IMAPTagGenerator()
  private var pendingTag: String?
  /// Follows the socket, not the last thing anyone asked it to do. It goes false
  /// the moment a command finds the connection gone, so a caller that reconnects
  /// on a dead socket has something true to read.
  public private(set) var isConnected = false
  private var selectedMailbox: String?
  private var selectedUIDValidity: UInt32 = 0

  private var isBusy = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  public init(
    channel: any IMAPByteChannel = NWConnectionChannel(),
    reader: any IMAPResponseReading = NIOIMAPResponseReader()
  ) {
    self.channel = channel
    self.reader = reader
  }

  // MARK: - Connect

  /// Opens the socket, then `LOGIN`.
  ///
  /// A `NO`/`BAD` on LOGIN becomes `authenticationFailed` rather than the
  /// generic `commandFailed`, because it is the one failure here with a user
  /// action attached: `IMAPMailConnectionService` maps it to
  /// `MailError.authenticationFailed`, and the connect screen can then say the
  /// app password was rejected instead of showing a network error.
  public func connect(_ credentials: IMAPCredentials) async throws {
    await acquire()
    defer { release() }

    reader.reset()
    isConnected = false
    selectedMailbox = nil
    selectedUIDValidity = 0

    try await channel.open(host: credentials.host, port: credentials.port)

    // The greeting (`* OK … ready`) arrives unsolicited before any command. It
    // is not awaited separately: LOGIN goes out immediately and the greeting is
    // one more untagged response read while waiting for LOGIN's tag. A `* BYE`
    // greeting — a server refusing the connection outright — surfaces through
    // the same path as any mid-command BYE.
    do {
      try await run(.login(tag: nextTag(), address: credentials.address, password: credentials.password))
    } catch let error as IMAPTransportError {
      await channel.close()
      if case .commandFailed(_, _, let text) = error {
        throw IMAPTransportError.authenticationFailed(text)
      }
      throw error
    } catch {
      await channel.close()
      throw error
    }

    isConnected = true
  }

  /// `LOGOUT`, then close. The LOGOUT is best-effort: if the server has already
  /// gone the socket still has to be released, and reporting a failure to
  /// disconnect helps nobody.
  public func disconnect() async throws {
    await acquire()
    defer { release() }

    if isConnected {
      try? await run(.logout(tag: nextTag()))
    }
    await channel.close()
    reader.reset()
    isConnected = false
    selectedMailbox = nil
    selectedUIDValidity = 0
  }

  // MARK: - Mailbox

  public func selectMailbox(_ name: String) async throws -> MailboxState {
    await acquire()
    defer { release() }
    return try await examine(name, force: true)
  }

  // MARK: - Search

  public func uids(since date: Date, in mailbox: String) async throws -> [UInt32] {
    await acquire()
    defer { release() }
    try await examine(mailbox, force: false)
    return try await search(.uidSearchSince(tag: nextTag(), date: date))
  }

  public func uids(since: Date, before: Date, in mailbox: String) async throws -> [UInt32] {
    await acquire()
    defer { release() }
    try await examine(mailbox, force: false)
    return try await search(.uidSearchBetween(tag: nextTag(), since: since, before: before))
  }

  public func uids(after uid: UInt32, in mailbox: String) async throws -> [UInt32] {
    await acquire()
    defer { release() }
    try await examine(mailbox, force: false)
    // `UID SEARCH UID n+1:*` always matches at least the highest existing UID,
    // even when nothing is new — the `*` means "the last message", not
    // "nothing". Filtering here keeps "these are new" true at the seam that
    // claims it, rather than making the engine re-ingest one message per sync.
    return try await search(.uidSearchAfter(tag: nextTag(), uid: uid)).filter { $0 > uid }
  }

  // MARK: - Fetch

  /// One `UID FETCH` for the set it was given. **No re-chunking** — the engine
  /// already bounded this to `MailSyncEngine.fetchBatchSize` so only one batch
  /// of message bodies exists at a time (§2.17).
  public func fetch(uids: [UInt32], in mailbox: String) async throws -> [MailMessage] {
    await acquire()
    defer { release() }

    guard !uids.isEmpty else { return [] }
    try await examine(mailbox, force: false)

    let tag = nextTag()
    try await send(.uidFetchBodyPeek(tag: tag, uids: uids))
    let events = try await readUntilComplete(tag: tag)

    var sequencer = IMAPFetchSequencer(tag: tag)
    try sequencer.apply(events)

    // `messages()` throws unless the tagged completion arrived, so a hangup
    // mid-fetch can never surface as a short batch (§2.16). The cursor then
    // stays put and these UIDs are re-fetched next sync, which the pipeline
    // absorbs as a no-op.
    let uidValidity = selectedUIDValidity
    let mailboxName = selectedMailbox ?? mailbox

    return try sequencer.messages().map { fetched in
      // The `Data` overload, deliberately: it tries UTF-8 then ISO-8859-1.
      // `String(decoding:as: UTF8.self)` would substitute U+FFFD for every
      // undecodable byte instead — silently corrupting exactly the Latin-1
      // bank mail this app exists to read, and taking the ₹ amount with it.
      try RFC822Message.parse(
        Data(fetched.bytes),
        uid: fetched.uid,
        uidValidity: uidValidity,
        mailboxName: mailboxName
      )
    }
  }

  // MARK: - Command plumbing
  //
  // Everything below assumes the mutex is already held.

  /// `EXAMINE`, never `SELECT` — read-only by construction (R4). The app has no
  /// business writing to a mailbox it does not own, and read-only-by-
  /// construction is a stronger guarantee than remembering not to issue a write.
  ///
  /// `force: false` re-examines only when the mailbox changed. IMAP requires a
  /// selected mailbox before UID SEARCH or UID FETCH, so every public method
  /// here is self-sufficient rather than trusting its caller to have selected —
  /// but re-issuing EXAMINE for every batch of a backfill would be a round trip
  /// per batch for nothing.
  @discardableResult
  private func examine(_ name: String, force: Bool) async throws -> MailboxState {
    if !force, selectedMailbox == name, selectedUIDValidity != 0 {
      return MailboxState(name: name, uidValidity: selectedUIDValidity, uidNext: 0)
    }

    let tag = nextTag()
    try await send(.examine(tag: tag, mailbox: name))
    let events = try await readUntilComplete(tag: tag)

    var uidValidity: UInt32?
    var uidNext: UInt32?
    for event in events {
      switch event {
      case .uidValidity(let value): uidValidity = value
      case .uidNext(let value): uidNext = value
      default: break
      }
    }

    // UIDVALIDITY is mandatory in an EXAMINE response and the entire UID cursor
    // is meaningless without it, so a server that omits it is a malformed
    // response rather than a mailbox with a default. UIDNEXT is advisory here —
    // the engine never reads it — so a missing one is zero.
    guard let uidValidity else {
      throw IMAPTransportError.malformedResponse("EXAMINE \(name) returned no UIDVALIDITY")
    }

    selectedMailbox = name
    selectedUIDValidity = uidValidity
    return MailboxState(name: name, uidValidity: uidValidity, uidNext: uidNext ?? 0)
  }

  private func search(_ command: IMAPCommand) async throws -> [UInt32] {
    try await send(command)
    // Accumulated across every `* SEARCH` line rather than taking the last: a
    // server may split results over more than one untagged response, and
    // keeping only the final line would silently drop most of a backfill.
    return try await readUntilComplete(tag: command.tag).flatMap { event -> [UInt32] in
      if case .searchResults(let uids) = event { return uids }
      return []
    }
  }

  private func run(_ command: IMAPCommand) async throws {
    try await send(command)
    _ = try await readUntilComplete(tag: command.tag)
  }

  private func send(_ command: IMAPCommand) async throws {
    pendingTag = command.tag
    do {
      try await channel.send(command.wireBytes)
    } catch {
      markDisconnected()
      throw error
    }
  }

  /// A command has just discovered the socket is gone.
  ///
  /// `selectedMailbox` is cleared with it, and that is the load-bearing half:
  /// `examine(force: false)` skips the EXAMINE when the mailbox is unchanged, so
  /// a fetcher that reconnected while still believing INBOX was selected would
  /// issue `UID SEARCH` against a connection with no selected mailbox and fail
  /// on every command after the reconnect.
  private func markDisconnected() {
    isConnected = false
    selectedMailbox = nil
    selectedUIDValidity = 0
  }

  /// Reads until the tagged completion for `tag`.
  ///
  /// Three terminations, and telling them apart is the whole job:
  ///
  /// - `OK` for our tag — done.
  /// - `NO`/`BAD` for our tag — the command failed, and says why.
  /// - `* BYE`, or the socket closing, *before* either — `serverClosedMidCommand`,
  ///   never a partial result. A hangup mid-command must not be
  ///   indistinguishable from a command that legitimately returned nothing;
  ///   that is the silent zero §2.16 built this layer to avoid.
  ///
  /// **The returned array includes the terminal `.commandCompleted`.**
  /// `IMAPFetchSequencer` tracks its own completion and refuses to hand back
  /// messages without seeing it — swallowing it here would make every fetch
  /// throw `serverClosedMidCommand` on an entirely healthy connection.
  ///
  /// Events are returned rather than streamed to a callback so that no caller
  /// has to capture a mutable local across an `await`. The memory is the same:
  /// the batch is already bounded to `MailSyncEngine.fetchBatchSize` upstream,
  /// and the sequencer would hold those bytes either way.
  private func readUntilComplete(tag: String) async throws -> [IMAPServerEvent] {
    var collected: [IMAPServerEvent] = []

    while true {
      let chunk: [UInt8]
      do {
        chunk = try await channel.receive()
      } catch {
        pendingTag = nil
        markDisconnected()
        throw IMAPTransportError.serverClosedMidCommand(tag: tag, text: "\(error)")
      }

      for event in try reader.consume(chunk) {
        collected.append(event)

        switch event {
        case .commandCompleted(let completedTag, let status, let text):
          // A completion for another tag is not ours and not an error; keep
          // reading.
          guard completedTag == tag else { continue }
          pendingTag = nil
          if status == .ok { return collected }
          throw IMAPTransportError.commandFailed(tag: tag, status: status, text: text)

        case .connectionClosing(let text):
          pendingTag = nil
          markDisconnected()
          throw IMAPTransportError.serverClosedMidCommand(tag: tag, text: text)

        default:
          continue
        }
      }
    }
  }

  private func nextTag() -> String {
    tags.next()
  }

  // MARK: - Exclusive access
  //
  // The in-actor mutex. Actor isolation keeps `isBusy` and `waiters` safe to
  // touch; what it does not do is keep one command's write and its reads
  // adjacent, and that is what this restores. Identical to `IngestPipeline`.

  private func acquire() async {
    while isBusy {
      await withCheckedContinuation { continuation in
        waiters.append(continuation)
      }
    }
    isBusy = true
  }

  private func release() {
    isBusy = false
    guard !waiters.isEmpty else { return }
    waiters.removeFirst().resume()
  }
}
