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

  /// The screen's state and actions (T2a). See `ConnectMailModel`.
  @State private var model: ConnectMailModel
  @State private var provider: MailProvider = .gmail
  @State private var address = ""
  @State private var host = ""
  @State private var password = ""

  public init(mailConnectionService: MailConnectionService, onBackfillStart: (() -> Void)? = nil) {
    self.mailConnectionService = mailConnectionService
    self.onBackfillStart = onBackfillStart
    _model = State(initialValue: ConnectMailModel(service: mailConnectionService))
  }

  private var canConnect: Bool {
    ConnectFormGate.isValid(provider: provider, address: address, host: host, password: password)
  }

  public var body: some View {
    Group {
      switch model.connectionState {
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
        let seen = model.observe(state)
        if seen.becameConnected { onBackfillStart?() }
        if let line = seen.announcement { announce(line) }
      }
    }
    .alert(
      "Something went wrong",
      isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } }),
      presenting: model.errorMessage,
      actions: { _ in Button("OK", role: .cancel) {} },
      message: { message in Text(message) }
    )
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
        if let attention = model.attention(now: Date()) {
          MailAttentionCard(copy: attention)
            .padding(.bottom, NomiSpacing.xxs)
        }
        if model.isReconnectOfferShown {
          reconnectCard
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
        if let errorText = model.errorText {
          errorLine(errorText)
            .padding(.top, NomiSpacing.sm)
        }
      }
      .padding(.horizontal, NomiSpacing.screenGutter)
      .padding(.bottom, NomiSpacing.sm)
      .disabled(model.isConnecting || model.connectionState == .connecting)
    }
    .safeAreaInset(edge: .bottom) {
      connectFooter
    }
  }

  /// The offer to reuse the saved password. The form below stays for a new one.
  private var reconnectCard: some View {
    VStack(alignment: .leading, spacing: NomiSpacing.sm) {
      Text("Your saved password is still on this device.")
        .nomiTextStyle(.body)
        .foregroundStyle(NomiColor.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
      Button("Try again") {
        model.tryAgain()
      }
      .buttonStyle(NomiPrimaryButtonStyle(height: 52))
    }
    .padding(NomiSpacing.sm)
    .frame(maxWidth: .infinity, alignment: .leading)
    .nomiCard(padding: EdgeInsets())
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
        model.connect(typedCredentials())
      } label: {
        if model.isConnecting {
          ProgressView()
            .tint(NomiColor.onPrimary)
        } else {
          Text("Connect")
        }
      }
      .buttonStyle(NomiPrimaryButtonStyle(height: 52))
      .disabled(!canConnect || model.isConnecting)

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
          SyncStatusRow(state: model.connectionState)
        }
        .padding(NomiSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nomiCard(padding: EdgeInsets())

        // Sync keeps its own card. Disconnect draws its own (NomiDestructiveRow),
        // so it sits outside this card rather than inside it.
        Button("Sync now") { model.syncNow() }
          .buttonStyle(NomiSecondaryButtonStyle())
          .frame(maxWidth: .infinity, minHeight: NomiSpacing.rowMinHeight, alignment: .leading)
          .padding(.horizontal, NomiSpacing.sm)
          .nomiCard(padding: EdgeInsets())
          .padding(.top, NomiSpacing.sm)

        NomiDestructiveRow(title: "Disconnect") { model.requestDisconnect() }
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
    .alert(
      "Disconnect mail?",
      isPresented: $model.isConfirmingDisconnect
    ) {
      Button("Disconnect", role: .destructive) { model.confirmDisconnect() }
      Button("Cancel", role: .cancel) { model.cancelDisconnect() }
    } message: {
      Text("Nomi stops scanning this mailbox and forgets the saved password. Your transactions stay in Nomi.")
    }
  }

  // MARK: - Actions

  /// The typed form values, as credentials. Trimmed values only: a pasted app
  /// password or address carrying a stray newline must never reach
  /// `IMAPCredentials`.
  private func typedCredentials() -> IMAPCredentials {
    let resolvedHost = provider.fixedHost ?? ConnectFormGate.normalized(host)
    return IMAPCredentials(
      host: resolvedHost,
      port: provider.port,
      address: ConnectFormGate.normalized(address),
      password: ConnectFormGate.normalized(password)
    )
  }
}

/// Whether the "Try again" offer shows (R5e, X15). Pure, so the rule is tested
/// without a view.
enum ReconnectOffer {
  static func isShown(state: MailConnectionState, hadConnection: Bool, hasStoredCredential: Bool) -> Bool {
    guard hasStoredCredential && hadConnection else { return false }
    switch state {
    case .failed, .disconnected: return true
    case .connecting, .connected: return false
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

#Preview("Connect mail — try again") {
  NavigationStack {
    ConnectMailScreen(mailConnectionService: SavedCredentialFailedFakeMailConnectionService())
  }
}

/// `errorMessage` lives on `ConnectMailModel`, not in `init`, so there is no
/// existing precedent in this codebase for seeding another view's
/// presented-alert state from a preview, same reasoning as `LedgerScreen`'s
/// delete-error preview. `.constant(true)` overlays the exact alert
/// `ConnectMailModel.syncNow` and `confirmDisconnect` present, atop the real
/// connected-state screen.
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
