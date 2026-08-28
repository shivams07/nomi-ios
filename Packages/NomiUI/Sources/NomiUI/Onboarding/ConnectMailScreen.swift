import NomiCore
import NomiPreview
import SwiftUI

/// The mail connect flow (U7): provider picker, app-password instructions,
/// credential entry. Also renders the connected/failed states so it doubles
/// as the disconnect screen — Settings pushes here for both directions.
/// Reads `Design/**`. Must not edit it.
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

  public init(mailConnectionService: MailConnectionService, onBackfillStart: (() -> Void)? = nil) {
    self.mailConnectionService = mailConnectionService
    self.onBackfillStart = onBackfillStart
  }

  private var canConnect: Bool {
    ConnectFormGate.isValid(provider: provider, address: address, host: host, password: password)
  }

  public var body: some View {
    Group {
      switch connectionState {
      case .connected(let connectedAddress, _):
        connectedView(address: connectedAddress)
      case .connecting:
        formView.disabled(true)
      case .disconnected, .failed:
        formView
      }
    }
    .scrollContentBackground(.hidden)
    .background(NomiColor.surfaceCanvas)
    .navigationTitle("Connect Mail")
    .task {
      for await state in mailConnectionService.state {
        connectionState = state
        if case .connected = state {
          onBackfillStart?()
        }
      }
    }
  }

  private var formView: some View {
    Form {
      Section("Provider") {
        Picker("Provider", selection: $provider) {
          ForEach(MailProvider.allCases) { option in
            Text(option.displayName).tag(option)
          }
        }
      }
      Section("Account") {
        TextField("Email address", text: $address)
          #if os(iOS)
          .keyboardType(.emailAddress)
          .textInputAutocapitalization(.never)
          #endif
          .autocorrectionDisabled()
        if provider.fixedHost == nil {
          TextField("IMAP host", text: $host)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
        }
        SecureField("Password", text: $password)
      }
      Section {
        Text(provider.passwordInstructions)
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.textTertiary)
      }
      Section {
        // §1.1: stated as body copy here, not a footnote — the point is that
        // it reads before the user commits a password, not after.
        Text("Your mail credential stays on this device. If you use Nomi on a second device, you'll need to enter it there too — your transactions still sync.")
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.textTertiary)
      }
      if case .failed(let error) = connectionState, didAttemptOnce {
        Section {
          Text(MailErrorMessage.text(for: error))
            .nomiTextStyle(.caption)
            .foregroundStyle(NomiColor.overBudget)
        }
      }
      Section {
        Button {
          connect()
        } label: {
          if isConnecting {
            ProgressView()
          } else {
            Text("Connect")
          }
        }
        .disabled(!canConnect || isConnecting)
      }
    }
  }

  private func connectedView(address: String) -> some View {
    List {
      Section {
        HStack {
          Text(address)
            .nomiTextStyle(.body)
            .foregroundStyle(NomiColor.textPrimary)
          Spacer()
          SyncStatusRow(state: connectionState)
        }
      }
      Section {
        Button("Sync now") {
          Task { try? await mailConnectionService.syncNow() }
        }
        Button("Disconnect", role: .destructive) {
          Task { try? await mailConnectionService.disconnect() }
        }
      }
      Section {
        // §1.1, restated here for the already-connected state: disconnecting
        // never touches transactions already synced.
        Text("Disconnecting stops new mail scans. Your transactions stay in Nomi.")
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.textTertiary)
      }
    }
    .scrollContentBackground(.hidden)
  }

  private func connect() {
    didAttemptOnce = true
    isConnecting = true
    let resolvedHost = provider.fixedHost ?? host
    let credentials = IMAPCredentials(host: resolvedHost, port: provider.port, address: address, password: password)
    Task {
      defer { isConnecting = false }
      try? await mailConnectionService.connect(credentials)
    }
  }
}

#Preview("Connect mail — form, dark") {
  NavigationStack {
    ConnectMailScreen(mailConnectionService: FakeMailConnectionService())
  }
  .preferredColorScheme(.dark)
}

#Preview("Connect mail — connected, dark") {
  NavigationStack {
    ConnectMailScreen(mailConnectionService: ConnectedFakeMailConnectionService())
  }
  .preferredColorScheme(.dark)
}

#Preview("Connect mail — failed, dark") {
  NavigationStack {
    ConnectMailScreen(mailConnectionService: FailedFakeMailConnectionService())
  }
  .preferredColorScheme(.dark)
}

#Preview("Connect mail — connecting, dark") {
  NavigationStack {
    ConnectMailScreen(mailConnectionService: ConnectingFakeMailConnectionService())
  }
  .preferredColorScheme(.dark)
}
