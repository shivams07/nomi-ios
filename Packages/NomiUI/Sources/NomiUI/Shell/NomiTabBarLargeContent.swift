#if os(iOS)
import SwiftUI
import UIKit

/// The tab bar's touch layer (F3c, I-16 Amendment 1, Shaun's L2). SwiftUI's large content
/// viewer takes the touch from a hold of about 0.2 s at accessibility sizes and selects
/// nothing on lift, so the viewer moves here. UIKit's `UILargeContentViewerInteraction`
/// shows the magnifier, and lifting selects the slot under the finger, as UITabBar does.
///
/// A transparent view covers the bar and owns every touch. The SwiftUI buttons keep
/// their drawing, VoiceOver and macOS, but take no touches on iOS. VoiceOver never
/// touches this layer: the container is hidden from accessibility, and VoiceOver
/// activates the SwiftUI buttons directly.
struct NomiTabBarTouchOverlay: UIViewRepresentable {
  /// Left to right: two leading tabs, the `+` ("Add transaction", "plus"), two trailing tabs.
  let items: [(title: String, symbolName: String)]
  /// Called with the slot index on a tap, or on a hold that lifts on a slot.
  let onSelectIndex: (Int) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(onSelectIndex: onSelectIndex)
  }

  func makeUIView(context: Context) -> NomiTabBarTouchView {
    let view = NomiTabBarTouchView()
    view.configure(items: items)
    let coordinator = context.coordinator
    coordinator.slotViews = view.slotViews

    let viewer = UILargeContentViewerInteraction(delegate: coordinator)
    view.addInteraction(viewer)

    // A tap that the viewer does not claim selects; a hold that becomes the viewer never
    // also taps, so a double select cannot pop a tab to its root.
    let tap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleTap(_:)))
    tap.require(toFail: viewer.gestureRecognizerForExclusionRelationship)
    view.addGestureRecognizer(tap)
    return view
  }

  func updateUIView(_ uiView: NomiTabBarTouchView, context: Context) {
    context.coordinator.onSelectIndex = onSelectIndex
    uiView.configure(items: items)
  }

  final class Coordinator: NSObject, UILargeContentViewerInteractionDelegate {
    var onSelectIndex: (Int) -> Void
    /// The five slot views, in slot order. Set once the touch view is built.
    var slotViews: [UIView] = []

    init(onSelectIndex: @escaping (Int) -> Void) {
      self.onSelectIndex = onSelectIndex
    }

    func largeContentViewerInteraction(
      _ interaction: UILargeContentViewerInteraction,
      itemAt point: CGPoint
    ) -> UILargeContentViewerItem? {
      guard let index = NomiTabBarHit.slot(atX: point.x), slotViews.indices.contains(index) else {
        return nil
      }
      return slotViews[index]
    }

    func largeContentViewerInteraction(
      _ interaction: UILargeContentViewerInteraction,
      didEndOn item: UILargeContentViewerItem?,
      at point: CGPoint
    ) {
      // A hold that ends outside the bar ends on no item, and selects nothing.
      guard let view = item as? UIView, let index = slotViews.firstIndex(where: { $0 === view }) else {
        return
      }
      onSelectIndex(index)
    }

    @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
      guard recognizer.state == .ended, let container = recognizer.view else { return }
      let point = recognizer.location(in: container)
      if let index = NomiTabBarHit.slot(atX: point.x) {
        onSelectIndex(index)
      }
    }
  }
}

/// The transparent container and its five slot views. Frames come from `NomiTabBarHit`
/// and `NomiTabBarMetrics`, so the slot a point lands on is the slot drawn there.
final class NomiTabBarTouchView: UIView {
  private(set) var slotViews: [UIView] = []

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    isMultipleTouchEnabled = false
    // VoiceOver uses the SwiftUI buttons. This layer is for touches only.
    accessibilityElementsHidden = true
    for _ in 0..<NomiTabBarHit.slotCount {
      let slot = UIView()
      slot.backgroundColor = .clear
      slot.showsLargeContentViewer = true
      slot.scalesLargeContentImage = true
      addSubview(slot)
      slotViews.append(slot)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("NomiTabBarTouchView is built in code")
  }

  func configure(items: [(title: String, symbolName: String)]) {
    for (index, item) in items.prefix(slotViews.count).enumerated() {
      let slot = slotViews[index]
      slot.largeContentTitle = item.title
      slot.largeContentImage = UIImage(systemName: item.symbolName)
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let size = NomiTabBarMetrics.slot
    let y = (bounds.height - size) / 2
    for (index, slot) in slotViews.enumerated() {
      let centre = NomiTabBarHit.centreX(of: index)
      slot.frame = CGRect(x: centre - size / 2, y: y, width: size, height: size)
    }
  }
}
#endif
