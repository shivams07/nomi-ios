#if canImport(UIKit)
import NomiUI
import SwiftUI
import UIKit

// SB2 of nomi-ios-statusbar-ruling (Shaun, 2026-11-09). The SwiftUI root
// controller cannot be given a light status bar, so a transparent overlay
// window one level above the app window supplies it. The overlay is shown only
// while a navy hero is under the status bar, and hidden otherwise, so the
// SwiftUI window governs the bar as before whenever the overlay is hidden.
// The tone is decided in NomiUI (`NomiStatusBarToneRule`); this file only acts
// on it.

/// The root controller of the overlay window. It asks for light glyphs and
/// never hides the bar. It forwards no child-controller overrides: the overlay
/// is in another window, and UIKit does not follow a child in another window
/// (ruling, finding 5).
final class StatusBarOverlayController: UIViewController {
  override func loadView() {
    let view = UIView()
    view.backgroundColor = .clear
    view.isUserInteractionEnabled = false
    self.view = view
  }

  override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

  override var prefersStatusBarHidden: Bool { false }
}

/// The overlay window passes every touch through to the app window below it.
/// Returning nil from hit testing makes the window invisible to touches, so
/// the tab bar, the gear, the pill and the sheets all keep working.
final class StatusBarOverlayWindow: UIWindow {
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    nil
  }
}

/// Owns the one overlay window and shows or hides it from the published tone.
/// iPhone only, one scene, so there is one overlay. Never made key: the app
/// window keeps keyboard and first-responder focus.
@MainActor
final class StatusBarOverlay {
  static let shared = StatusBarOverlay()

  private var window: StatusBarOverlayWindow?
  /// The latest tone, kept so a tone that arrives before the window does is
  /// honoured when `attach` builds it.
  private var tone: NomiStatusBarTone?

  /// Builds the overlay in `host`'s scene the first time a host window is
  /// known. Later calls do nothing, so there is never a second overlay.
  func attach(to host: UIWindow) {
    guard window == nil, let scene = host.windowScene else { return }
    let overlay = StatusBarOverlayWindow(windowScene: scene)
    overlay.windowLevel = .normal + 1
    overlay.backgroundColor = .clear
    overlay.isUserInteractionEnabled = false
    overlay.accessibilityElementsHidden = true
    overlay.rootViewController = StatusBarOverlayController()
    overlay.isHidden = !NomiStatusBarToneRule.showsLightOverlay(tone)
    window = overlay
  }

  /// Applies the tone published by the screens. Shown only for `.light`.
  func apply(_ newTone: NomiStatusBarTone?) {
    tone = newTone
    window?.isHidden = !NomiStatusBarToneRule.showsLightOverlay(newTone)
  }

  /// Whether the overlay is currently on screen. Read by tests.
  var isOverlayVisible: Bool {
    window.map { !$0.isHidden } ?? false
  }
}

/// A zero-size view that attaches the overlay once it is in a window. Placed as
/// a background of the root container, so it lives as long as the app does.
struct StatusBarOverlayAnchor: UIViewRepresentable {
  func makeUIView(context: Context) -> AnchorView {
    AnchorView()
  }

  func updateUIView(_ uiView: AnchorView, context: Context) {}

  final class AnchorView: UIView {
    override func didMoveToWindow() {
      super.didMoveToWindow()
      guard let host = window else { return }
      MainActor.assumeIsolated {
        StatusBarOverlay.shared.attach(to: host)
      }
    }
  }
}
#endif
