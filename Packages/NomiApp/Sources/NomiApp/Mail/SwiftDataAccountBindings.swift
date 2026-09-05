import Foundation
import NomiCore
import NomiIngest
import SwiftData

/// The first real `AccountBindingResolving` (C4). Answers
/// `(senderDomain, cardFragment) -> accountID` from the `AccountBinding` table
/// that `SwiftDataTransactionStore.setAccount` writes.
///
/// **Why it owns a private `ModelContext` on a serial queue.**
/// `MailSyncEngine.classify` is `nonisolated` and calls the extractor
/// synchronously, so this has to answer without awaiting and from whatever
/// thread the sync happens to be on. A `ModelContext` is not `Sendable` and
/// must not be touched from two threads, so it is confined to one private
/// serial queue and every call hops onto it. The bindings table is tiny - one
/// row per account the user has ever assigned - and the fetch is always fresh,
/// which is what a learning loop needs: a binding written a second ago must be
/// visible to the next message in the same sync.
///
/// `@unchecked Sendable` because the compiler cannot see that the queue is what
/// protects the context. That is the whole of the unchecked part.
public final class SwiftDataAccountBindings: AccountBindingResolving, @unchecked Sendable {
  private let context: ModelContext
  private let queue = DispatchQueue(label: "com.shivams07.nomi.account-bindings")

  public init(container: ModelContainer) {
    self.context = ModelContext(container)
  }

  /// `nil` is the normal answer, not a failure: §1.2 says leave `accountID` nil
  /// and flag for review rather than guess, because a wrong account is
  /// *silently* wrong.
  ///
  /// Normalisation is `AccountBindingKey`'s and nowhere else's - the same
  /// function `MailTransactionExtractor` stamps rows with. A fragment that is
  /// not four digits cannot have been written by that path, so it cannot match.
  public func accountID(senderDomain: String, cardFragment: String) -> UUID? {
    let domain = AccountBindingKey.domain(senderDomain)
    guard let fragment = AccountBindingKey.fragment(cardFragment) else { return nil }

    return queue.sync {
      let descriptor = FetchDescriptor<AccountBinding>(
        predicate: #Predicate<AccountBinding> {
          $0.senderDomain == domain && $0.cardFragment == fragment
        }
      )
      guard let rows = try? context.fetch(descriptor), !rows.isEmpty else { return nil }
      // CloudKit forbids unique constraints (R5), so two devices can each write
      // a binding for the same key. Lowest id wins - an arbitrary rule, but a
      // *stable* one, so both devices resolve to the same account rather than
      // to whatever fetch order returned. `SwiftDataBudgetStore` takes the
      // oldest row for the same reason; `AccountBinding` has no `createdAt`.
      return rows.min { $0.id.uuidString < $1.id.uuidString }?.accountID
    }
  }
}
