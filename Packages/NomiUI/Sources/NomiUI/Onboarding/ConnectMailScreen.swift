#if os(iOS)
import UIKit
#endif
import NomiCore
import NomiPreview
import SwiftUI

/// Connect mail (ConnectMail and ConnectMailAttention artboards, SIMP §3 item 5).
/// The form opens with the provider chips, the provider's steps and the two
/// fields. The Connect button is pinned at the bottom, and the footnote under it
/// says what is kept and what is read.
///
/// Also renders the connected state, so Settings can push here to manage the
/// connection: the account card, Check now, Scan last 6 months, and Disconnect.
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
    self.init(
      mailConnectionService: mailConnectionService,
      onBackfillStart: onBackfillStart,
      startingProvider: .gmail
    )
  }

  /// The provider the form opens on. The public init opens on Gmail; previews and
  /// the visual check open each provider through this one.
  init(
    mailConnectionService: MailConnectionService,
    onBackfillStart: (() -> Void)?,
    startingProvider: MailProvider
  ) {
    self.mailConnectionService = mailConnectionService
    self.onBackfillStart = onBackfillStart
    _model = State(initialValue: ConnectMailModel(service: mailConnectionService))
    _provider = State(initialValue: startingProvider)
  }

  private var canConnect: Bool {
    ConnectFormGate.isValid(provider: provider, address: address, host: host, password: password)
  }

  /// The connected view keeps the large title; the form's own h1 names the provider.
  private var isConnected: Bool {
    if case .connected = model.connectionState { return true }
    return false
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
    .navigationBarTitleDisplayMode(isConnected ? .large : .inline)
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
        Text("Connect \(provider.displayName)")
          .nomiTextStyle(.title)
          .foregroundStyle(NomiColor.ink)
          .accessibilityAddTraits(.isHeader)
          .padding(.bottom, NomiSpacing.sm)
        providerChips
          .padding(.bottom, NomiSpacing.sm)
        if let title = provider.guideTitle {
          stepsCard(title: title)
        } else {
          genericNote
        }
        fieldsBlock
          .padding(.top, NomiSpacing.sm)
        if let errorText = model.errorText {
          errorLine(errorText)
            .padding(.top, NomiSpacing.sm)
        }
        // The footnote scrolls with the form, so at AX3 it never covers the fields.
        Text(ConnectMailFootnote.text)
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.inkSecondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
          .padding(.top, NomiSpacing.sm)
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

  /// One chip per provider the app connects to. The selected chip is black.
  private var providerChips: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: NomiSpacing.xs) {
        ForEach(MailProvider.allCases) { option in
          providerChip(option)
        }
      }
    }
    .fixedSize(horizontal: false, vertical: true)
  }

  private func providerChip(_ option: MailProvider) -> some View {
    let isSelected = provider == option
    return Button {
      provider = option
    } label: {
      Text(option.displayName)
        .nomiTextStyle(.label)
        .foregroundStyle(isSelected ? NomiColor.card : NomiColor.ink)
        .padding(.horizontal, NomiSpacing.sm)
        .frame(minHeight: 40)
        .background(Capsule().fill(isSelected ? NomiColor.ink : NomiColor.card))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  /// The numbered steps for the chosen provider, and its app-password page.
  private func stepsCard(title: String) -> some View {
    VStack(alignment: .leading, spacing: NomiSpacing.sm) {
      Text(title)
        .nomiTextStyle(.rowTitle)
        .foregroundStyle(NomiColor.ink)
      ForEach(Array(provider.steps.enumerated()), id: \.offset) { index, step in
        HStack(alignment: .top, spacing: NomiSpacing.sm) {
          Text("\(index + 1)")
            .nomiTextStyle(.label)
            .foregroundStyle(NomiColor.inkDeep)
            .frame(width: 34, height: 34)
            .background(Circle().fill(NomiColor.secondaryFill))
          Text(step)
            .nomiTextStyle(.body)
            .foregroundStyle(NomiColor.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      if let url = provider.appPasswordURL, let linkTitle = provider.appPasswordLinkTitle {
        Link(destination: url) {
          Text(linkTitle)
            .nomiTextStyle(.label)
            .foregroundStyle(NomiColor.primary)
            .frame(minHeight: NomiSpacing.rowMinHeight, alignment: .leading)
        }
      }
    }
    .padding(NomiSpacing.sm)
    .frame(maxWidth: .infinity, alignment: .leading)
    .nomiCard(padding: EdgeInsets())
  }

  /// Generic IMAP has no steps: the user's own provider issues the password.
  private var genericNote: some View {
    Text(MailProvider.genericPasswordNote)
      .nomiTextStyle(.caption)
      .foregroundStyle(NomiColor.inkSecondary)
      .padding(.horizontal, NomiSpacing.xxs)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// The address, the IMAP host for generic IMAP only, and the app password.
  private var fieldsBlock: some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
      fieldLabel("Email address")
      fieldBox {
        TextField("Email address", text: $address)
          #if os(iOS)
          .keyboardType(.emailAddress)
          .textInputAutocapitalization(.never)
          #endif
          .autocorrectionDisabled()
      }
      if provider.fixedHost == nil {
        fieldLabel("IMAP host")
        fieldBox {
          TextField("IMAP host", text: $host)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
        }
      }
      fieldLabel("App password")
      fieldBox {
        SecureField("App password", text: $password)
        #if os(iOS)
        Button("Paste") { pasteFromClipboard() }
          .nomiTextStyle(.label)
          .foregroundStyle(NomiColor.primary)
          .frame(minHeight: NomiSpacing.rowMinHeight)
        #endif
      }
    }
  }

  private func fieldLabel(_ title: String) -> some View {
    Text(title)
      .nomiTextStyle(.label)
      .foregroundStyle(NomiColor.inkDeep)
      .padding(.top, NomiSpacing.xs)
      .padding(.horizontal, NomiSpacing.xxs)
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityHidden(true)
  }

  /// A 54 pt field: the card fill, an 18 pt radius and a hairline stroke.
  private func fieldBox<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    HStack(spacing: NomiSpacing.xs) {
      content()
    }
    .nomiTextStyle(.body)
    .foregroundStyle(NomiColor.ink)
    .padding(.horizontal, NomiSpacing.sm)
    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: NomiRadius.inset, style: NomiRadius.cardSheetStyle)
        .fill(NomiColor.card)
    )
    .overlay(
      RoundedRectangle(cornerRadius: NomiRadius.inset, style: NomiRadius.cardSheetStyle)
        .stroke(NomiColor.separator, lineWidth: 1)
    )
  }

  /// The clipboard is read only on this tap. Nothing reads it on appearance.
  private func pasteFromClipboard() {
    #if os(iOS)
    if let text = UIPasteboard.general.string {
      password = text
    }
    #endif
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

  /// Pinned Connect button, with the footnote under it. The footnote's claims are
  /// checked in `ConnectMailFootnote` and `ConnectMailCopy`.
  private var connectFooter: some View {
    VStack(spacing: NomiSpacing.xs) {
      Button {
        model.connect(typedCredentials())
      } label: {
        if model.isConnecting {
          ProgressView()
            .tint(NomiColor.onPrimary)
        } else {
          Text("Connect and scan 6 months")
        }
      }
      .buttonStyle(NomiPrimaryButtonStyle(height: 52))
      .disabled(!canConnect || model.isConnecting)
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
          checkedLine
        }
        .padding(NomiSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nomiCard(padding: EdgeInsets())

        // Check now and Scan last 6 months share one card. Disconnect draws its
        // own (NomiDestructiveRow), so it sits outside, as the artboard has it.
        VStack(spacing: 0) {
          connectedRow("Check now") { model.syncNow() }
          cardDivider
          connectedRow("Scan last 6 months") { model.scanRecent { onBackfillStart?() } }
        }
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

  /// "Checked <relative>" once a sync has landed; otherwise the shared status row.
  @ViewBuilder private var checkedLine: some View {
    if case .connected(_, let lastSync?) = model.connectionState {
      Text("Checked \(SyncStatusRow.relativeSyncPhrase(lastSync, now: Date()))")
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.inkSecondary)
    } else {
      SyncStatusRow(state: model.connectionState)
    }
  }

  private func connectedRow(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: NomiSpacing.sm) {
        Text(title)
          .nomiTextStyle(.body)
          .foregroundStyle(NomiColor.ink)
        Spacer(minLength: 0)
        Image(systemName: "chevron.right")
          .foregroundStyle(NomiColor.inkSecondary)
          .accessibilityHidden(true)
      }
      .frame(maxWidth: .infinity, minHeight: NomiSpacing.rowMinHeight, alignment: .leading)
      .padding(.horizontal, NomiSpacing.sm)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private var cardDivider: some View {
    Rectangle()
      .fill(NomiColor.separator)
      .frame(height: 1)
      .padding(.horizontal, NomiSpacing.sm)
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

#Preview("Connect mail — Zoho steps") {
  NavigationStack {
    ConnectMailScreen(
      mailConnectionService: FakeMailConnectionService(),
      onBackfillStart: nil,
      startingProvider: .zoho
    )
  }
}

#Preview("Connect mail — generic IMAP") {
  NavigationStack {
    ConnectMailScreen(
      mailConnectionService: FakeMailConnectionService(),
      onBackfillStart: nil,
      startingProvider: .generic
    )
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
