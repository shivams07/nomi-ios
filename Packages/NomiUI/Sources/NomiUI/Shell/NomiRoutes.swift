import SwiftUI

// clt-harness: include

/// Destinations pushed on the Home stack (F3, I-4). The Home stack attaches
/// `navigationDestination(for: HomeRoute.self)`.
public enum HomeRoute: Hashable, Sendable {
  case settings
  case connectMail
}

/// Opens the transaction entry sheet from anywhere in the app. The root sets it
/// with `\.nomiAddTransaction`.
public struct NomiAddTransactionAction: Sendable {
  private let run: @MainActor @Sendable () -> Void

  public init(_ run: @escaping @MainActor @Sendable () -> Void) {
    self.run = run
  }

  @MainActor
  public func callAsFunction() {
    run()
  }
}

private struct NomiAddTransactionActionKey: EnvironmentKey {
  static let defaultValue: NomiAddTransactionAction? = nil
}

public extension EnvironmentValues {
  /// The "Add transaction" action. It defaults to nil, and callers hide their
  /// "Add transaction" buttons while it is nil.
  var nomiAddTransaction: NomiAddTransactionAction? {
    get { self[NomiAddTransactionActionKey.self] }
    set { self[NomiAddTransactionActionKey.self] = newValue }
  }
}
