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
  /// Credential, notifications, files and preferences were cleared, but the store
  /// save failed and some rows remain. Retrying is safe.
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
