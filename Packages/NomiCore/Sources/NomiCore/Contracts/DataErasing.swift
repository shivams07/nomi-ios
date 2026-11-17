import Foundation

/// What an erase can reach, decided from `StorageMode` each time it is read.
///
/// `everywhere`: the CloudKit mirror is running, so deletes reach iCloud.
/// `thisDeviceOnly`: local rows go, but a copy in iCloud can come back when sync
/// resumes. Also used for a local fallback store and for every paused account.
/// `unavailable`: the real store was never opened for this launch, so there is
/// nothing an erase can reach. Erasing refuses.
public enum EraseScope: Sendable, Equatable {
  case everywhere
  case thisDeviceOnly
  case unavailable(reason: String)
}

/// The three ways an erase can end without having finished cleanly.
public enum EraseError: Error, Sendable, Equatable {
  /// Thrown before anything is touched.
  case unavailable(reason: String)
  /// A sync did not stop within 30 s. Nothing was erased.
  case busy
  /// Some step did not finish. Every other step still ran and the gate is open,
  /// and retrying is safe. Which step failed decides what is left:
  /// - Rows remain: a delete or the store save failed. A later save in the same
  ///   erase can commit some of those deletes, so some rows may already be gone.
  /// - Default categories and rules may be missing: a reseed failed. When that is
  ///   the only failure, no user data remains. A retry, or the next launch,
  ///   restores the defaults.
  /// - A mail credential is still on this device: its delete failed.
  case incomplete
}

/// The erase-everything seam that Settings calls (S9a). Implemented in NomiApp
/// by `DataEraser`, which runs the order of operations in I-13 Amendment 1.
@MainActor
public protocol DataErasing: AnyObject {
  /// Read from the current StorageMode each time; S9a chooses its confirmation copy from it.
  var scope: EraseScope { get }
  /// The order of operations in B5 step 2. Returns only when nothing can write behind it.
  func eraseEverything() async throws
}
