import NomiCore
import NomiPreview
import SwiftUI

/// Connect mail (ConnectMail and ConnectMailAttention artboards, SIMP §3 item 5).
/// H0 large title. Provider and account fields sit on cards. The Connect button
/// is pinned at the bottom, and the credential caption is its footer.
///
/// Also renders the connected state, so Settings can push here to manage the
/// connection. That state has no artboard; it uses the same card and row
/// tokens as the form.
public struct ConnectMailScreen: View {
  public let mailConnectionService: MailConnectionService
  public var onBackfillStart: (() -> Void)?

  @State private var connectionState: MailConnectionState = .disconnected
  @State private var provider: MailProvider = .gmail
  @State private var address = ""
  @State private var host = ""
  @State private var password = ""
  @State private var isConnecting = false
  @State private var didAttemptOnce = false
  @State private var errorMessage: String?
  /// What this screen knows of the connection. The state stream carries
  /// `lastSync` only while connected, so these are what the attention card
  /// needs to say "Last synced …" after a disconnect. Seeded from the persisted
  /// history in `init`, so a relaunch does not start from "never connected".
  @State private var hadConnection: Bool
  @State private var lastKnownSync: Date?

  public init(mailConnectionService: MailConnectionService, onBackfillStart: (() -> Void)? = nil) {
    self.mailConnectionService = mailConnectionService
    self.onBackfillStart = onBackfillStart
    // `history` is synchronous and already on disk; read it before the state
    // loop in `.task` starts, so the first render carries the right card.
    let seed = MailAttentionSeed(history: mailConnectionService.history)
    _hadConnection = State(initialValue: seed.hadConnection)
    _lastKnownSync = State(initialValue: seed.lastSync)
  }

  private var canConnect: Bool {
    ConnectFormGate.isValid(provider: provider, address: address, host: host, password: password)
  }

  /// The inline error line already says what failed on the last attempt, so the
  /// attention card stays out of its way.
  private var attention: MailAttentionCopy? {
    if didAttemptOnce, case .failed = connectionState { return nil }
    return MailAttentionLogic.copy(
      for: connectionState,
      hadConnection: hadConnection,
      lastSync: lastKnownSync,
      now: Date()
    )
  }

  private var errorText: String? {
    guard didAttemptOnce, case .failed(let error) = connectionState else { return nil }
    return MailErrorMessage.text(for: error)
  }

  public var body: some View {
    Group {
      switch connectionState {
      case .connected(let connectedAddress, _):
        connectedView(address: connectedAddress)
      case .connecting, .disconnected, .failed:
        formView
      }
    }
    .background(NomiColor.ground.ignoresSafeArea())
    .navigationTitle("Connect mail")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.large)
    #endif
    .task {
      for await state in mailConnectionService.state {
        observe(state)
      }
    }
    .alert(
      "Something went wrong",
      isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }),
      presenting: errorMessage,
      actions: { _ in Button("OK", role: .cancel) {} },
      message: { message in Text(message) }
    )
  }

  private func observe(_ state: MailConnectionState) {
    connectionState = state
    if case .connected(_, let lastSync) = state {
      hadConnection = true
      if let lastSync { lastKnownSync = lastSync }
      onBackfillStart?()
    }
    // A failed attempt is announced here, not on appearance: the error line
    // is inserted with its text already set, which `onChange` would miss.
    if didAttemptOnce, case .failed(let error) = state {
      announce(MailErrorMessage.text(for: error))
    }
  }

  private func announce(_ message: String) {
    #if os(iOS)
    AccessibilityNotification.Announcement(message).post()
    #endif
  }

  // MARK: - Form

  private var formView: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        if let attention {
          MailAttentionCard(copy: attention)
            .padding(.bottom, NomiSpacing.xxs)
        }
        sectionLabel("Provider", isFirst: true)
        providerCard
        sectionLabel("Account")
        accountCard
        Text(provider.passwordInstructions)
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.inkSecondary)
          .padding(.top, NomiSpacing.xs + NomiSpacing.xxs)
          .padding(.horizontal, NomiSpacing.xxs)
        if let errorText {
          errorLine(errorText)
            .padding(.top, NomiSpacing.sm)
        }
      }
      .padding(.horizontal, NomiSpacing.screenGutter)
      .padding(.bottom, NomiSpacing.sm)
      .disabled(isConnecting || connectionState == .connecting)
    }
    .safeAreaInset(edge: .bottom) {
      connectFooter
    }
  }

  private func sectionLabel(_ title: String, isFirst: Bool = false) -> some View {
    Text(title)
      .nomiTextStyle(.label)
      .foregroundStyle(NomiColor.inkDeep)
      .padding(.top, isFirst ? 0 : NomiSpacing.sm)
      .padding(.bottom, NomiSpacing.xs)
      .padding(.horizontal, NomiSpacing.xxs)
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityAddTraits(.isHeader)
  }

  private var providerCard: some View {
    cardRow {
      Picker("Provider", selection: $provider) {
        ForEach(MailProvider.allCases) { option in
          Text(option.displayName).tag(option)
        }
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .tint(NomiColor.ink)
    }
    .nomiCard(padding: EdgeInsets())
  }

  private var accountCard: some View {
    VStack(spacing: 0) {
      cardRow {
        TextField("Email address", text: $address)
          #if os(iOS)
          .keyboardType(.emailAddress)
          .textInputAutocapitalization(.never)
          #endif
          .autocorrectionDisabled()
      }
      if provider.fixedHost == nil {
        cardDivider
        cardRow {
          TextField("IMAP host", text: $host)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
        }
      }
      cardDivider
      cardRow {
        SecureField("Password", text: $password)
      }
    }
    .nomiCard(padding: EdgeInsets())
  }

  /// A 56-high field row with the body style and 16 pt side padding.
  private func cardRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    content()
      .nomiTextStyle(.body)
      .foregroundStyle(NomiColor.ink)
      .padding(.horizontal, NomiSpacing.sm)
      .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
  }

  private var cardDivider: some View {
    Rectangle()
      .fill(NomiColor.separator)
      .frame(height: 1)
      .padding(.horizontal, NomiSpacing.sm)
  }

  /// The error line is the only red text on the screen. It carries an icon, so
  /// colour is not the only signal.
  private func errorLine(_ message: String) -> some View {
    HStack(alignment: .top, spacing: NomiSpacing.xs) {
      Image(systemName: "exclamationmark.circle")
        .foregroundStyle(NomiColor.error)
        .accessibilityHidden(true)
      Text(message)
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.error)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isStaticText)
    }
    .padding(.horizontal, NomiSpacing.xxs)
  }

  /// Pinned Connect button, with the credential caption under it as a footer
  /// (SIMP §3 item 5). The caption's claims are checked in `ConnectMailCopy`.
  private var connectFooter: some View {
    VStack(spacing: NomiSpacing.xs) {
      Button {
        connect()
      } label: {
        if isConnecting {
          ProgressView()
            .tint(NomiColor.onPrimary)
        } else {
          Text("Connect")
        }
      }
      .buttonStyle(NomiPrimaryButtonStyle(height: 52))
      .disabled(!canConnect || isConnecting)

      Text(ConnectMailCopy.credentialCaption)
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.inkSecondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
    .padding(.horizontal, NomiSpacing.screenGutter)
    .padding(.top, NomiSpacing.xs + NomiSpacing.xxs)
    .padding(.bottom, NomiSpacing.xs)
    .frame(maxWidth: .infinity)
    .background(NomiColor.ground)
  }

  // MARK: - Connected

  private func connectedView(address: String) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
          Text(address)
            .nomiTextStyle(.rowTitle)
            .foregroundStyle(NomiColor.ink)
          SyncStatusRow(state: connectionState)
        }
        .padding(NomiSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nomiCard(padding: EdgeInsets())

        VStack(spacing: 0) {
          Button("Sync now") { syncNow() }
            .buttonStyle(NomiSecondaryButtonStyle())
            .frame(maxWidth: .infinity, minHeight: NomiSpacing.rowMinHeight, alignment: .leading)
            .padding(.horizontal, NomiSpacing.sm)
          cardDivider
          NomiDestructiveRow(title: "Disconnect") { disconnect() }
            .padding(.horizontal, NomiSpacing.sm)
        }
        .nomiCard(padding: EdgeInsets())
        .padding(.top, NomiSpacing.sm)

        // Disconnecting never touches transactions already synced.
        Text("Disconnecting stops new mail scans. Your transactions stay in Nomi.")
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.inkSecondary)
          .padding(.top, NomiSpacing.xs + NomiSpacing.xxs)
          .padding(.horizontal, NomiSpacing.xxs)
      }
      .padding(.horizontal, NomiSpacing.screenGutter)
      .padding(.bottom, NomiSpacing.sm)
    }
  }

  // MARK: - Actions

  private func connect() {
    didAttemptOnce = true
    isConnecting = true
    // Trimmed values only — a pasted app password or address carrying a
    // stray newline must never reach `IMAPCredentials`. `try?` here is
    // deliberate, not an oversight: a failed connect already renders through
    // `connectionState`'s `.failed` case above, so a second, separate alert
    // would just repeat the same message.
    let resolvedHost = provider.fixedHost ?? ConnectFormGate.normalized(host)
    let credentials = IMAPCredentials(
      host: resolvedHost,
      port: provider.port,
      address: ConnectFormGate.normalized(address),
      password: ConnectFormGate.normalized(password)
    )
    Task {
      defer { isConnecting = false }
      try? await mailConnectionService.connect(credentials)
    }
  }

  private func syncNow() {
    Task {
      do {
        try await mailConnectionService.syncNow()
      } catch {
        errorMessage = "Couldn't sync right now. Try again in a moment."
      }
    }
  }

  private func disconnect() {
    Task {
      do {
        try await mailConnectionService.disconnect()
      } catch {
        errorMessage = "Couldn't disconnect right now. Try again in a moment."
      }
    }
  }
}

/// The attention card (ConnectMailAttention artboard): an errorTint tile with
/// an icon, the title in error, and the body in secondary ink. It is a status,
/// not a control, so it is not a button.
private struct MailAttentionCard: View {
  let copy: MailAttentionCopy

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      ZStack {
        Circle()
          .fill(NomiColor.errorTint)
        Image(systemName: "exclamationmark.circle")
          .resizable()
          .scaledToFit()
          .frame(width: 20, height: 20)
          .foregroundStyle(NomiColor.error)
      }
      .frame(width: 40, height: 40)
      .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
        Text(copy.title)
          .nomiTextStyle(.rowTitle)
          .foregroundStyle(NomiColor.error)
        Text(copy.message)
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.inkSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(NomiSpacing.sm)
    .frame(maxWidth: .infinity, alignment: .leading)
    .nomiCard(padding: EdgeInsets())
    .accessibilityElement(children: .combine)
  }
}

#Preview("Connect mail — form") {
  NavigationStack {
    ConnectMailScreen(mailConnectionService: FakeMailConnectionService())
  }
}

#Preview("Connect mail — connected") {
  NavigationStack {
    ConnectMailScreen(mailConnectionService: ConnectedFakeMailConnectionService())
  }
}

#Preview("Connect mail — failed") {
  NavigationStack {
    ConnectMailScreen(mailConnectionService: FailedFakeMailConnectionService())
  }
}

#Preview("Connect mail — connecting") {
  NavigationStack {
    ConnectMailScreen(mailConnectionService: ConnectingFakeMailConnectionService())
  }
}

/// `errorMessage` is private `@State`, not exposed via `init` — there is no
/// existing precedent in this codebase for seeding another view's
/// presented-alert state from a preview, same reasoning as `LedgerScreen`'s
/// delete-error preview. `.constant(true)` overlays the exact alert
/// `syncNow`/`disconnect` present, atop the real connected-state screen.
#Preview("Connect mail — sync error alert") {
  NavigationStack {
    ConnectMailScreen(mailConnectionService: ConnectedFakeMailConnectionService())
  }
  .alert("Something went wrong", isPresented: .constant(true)) {
    Button("OK", role: .cancel) {}
  } message: {
    Text("Couldn't sync right now. Try again in a moment.")
  }
}
