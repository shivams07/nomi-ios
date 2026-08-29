import NomiApp
import SwiftUI

/// The one file U0 and U8 share (design §"Files touched"). U0 created it as the
/// `@main` stub CI needs; U8 replaces its body with `NomiAppScene()`.
///
/// It stays one line on purpose. This target compiles at `SWIFT_VERSION 6.0`
/// while every package is Swift 5 with targeted concurrency, so anything that
/// lives here is held to a stricter standard than the code it would call — and
/// the composition root belongs in `NomiApp` regardless, where it can be read
/// and changed without touching the app target.
@main
struct Nomi: App {
  var body: some Scene {
    NomiAppScene()
  }
}
