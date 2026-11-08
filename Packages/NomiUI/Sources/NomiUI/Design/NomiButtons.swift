import SwiftUI

// clt-harness: include

/// Primary control: black capsule, white label, the one primary per screen.
/// Disabled drops to 40% opacity.
public struct NomiPrimaryButtonStyle: ButtonStyle {
  public let height: CGFloat

  public init(height: CGFloat = 54) {
    self.height = height
  }

  public func makeBody(configuration: Configuration) -> some View {
    NomiPrimaryButtonBody(configuration: configuration, height: height)
  }
}

/// Navy text, no fill, at least 44 pt high. For light grounds only: navy on a
/// hero or the Backfill gradient is unreadable (1.10:1). Use
/// `NomiHeroButtonStyle` there.
public struct NomiSecondaryButtonStyle: ButtonStyle {
  public init() {}

  public func makeBody(configuration: Configuration) -> some View {
    NomiSecondaryButtonBody(configuration: configuration)
  }
}

/// Buttons on a hero or the Backfill gradient (DEC-09).
///
/// `.primary` is a white capsule with a `navyDeep` label (17.08:1). `.secondary`
/// is dark `heroControl` glass with a white label (12.68:1 at the top of the
/// Backfill button, 11.37:1 at the bottom).
public struct NomiHeroButtonStyle: ButtonStyle {
  public enum Kind: Sendable {
    case primary
    case secondary
  }

  public let kind: Kind

  public init(_ kind: Kind) {
    self.kind = kind
  }

  public func makeBody(configuration: Configuration) -> some View {
    NomiHeroButtonBody(configuration: configuration, kind: kind)
  }

  // Token sources, pinned by NomiComponentsTests (A-09).
  static let primaryFill = NomiColor.heroText
  static let primaryLabel = NomiColor.navyDeep
  static let secondaryFill = NomiColor.heroGlassFill
  static let secondaryBorder = NomiColor.heroGlassBorder
}

/// A 44 x 44 navy glyph at 22 pt. Wrap it in a Button or NavigationLink and set
/// the accessibility label there.
public struct NomiNavIcon: View {
  public let systemName: String

  public init(systemName: String) {
    self.systemName = systemName
  }

  public var body: some View {
    Image(systemName: systemName)
      .resizable()
      .scaledToFit()
      .frame(width: 22, height: 22)
      .foregroundStyle(NomiColor.navy)
      .frame(width: 44, height: 44)
      .contentShape(Rectangle())
  }
}

/// A 44 pt circle of `heroControl` glass with a white glyph at 22 pt. For use on
/// a hero.
public struct NomiHeroIcon: View {
  public let systemName: String

  public init(systemName: String) {
    self.systemName = systemName
  }

  public var body: some View {
    Image(systemName: systemName)
      .resizable()
      .scaledToFit()
      .frame(width: 22, height: 22)
      .foregroundStyle(NomiColor.heroText)
      .frame(width: 44, height: 44)
      .nomiGlass(.heroControl, in: Circle())
  }
}

/// A destructive row: `error` text, leading, at least 52 pt high, no fill.
public struct NomiDestructiveRow: View {
  public let title: String
  public let action: () -> Void

  public init(title: String, action: @escaping () -> Void) {
    self.title = title
    self.action = action
  }

  public var body: some View {
    Button(action: action) {
      Text(title)
        .nomiTextStyle(.rowTitle)
        .foregroundStyle(NomiColor.error)
        .frame(maxWidth: .infinity, minHeight: NomiSpacing.rowMinHeight, alignment: .leading)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Style bodies

private struct NomiPrimaryButtonBody: View {
  let configuration: ButtonStyleConfiguration
  let height: CGFloat

  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    configuration.label
      .nomiTextStyle(.button)
      .foregroundStyle(NomiColor.onPrimary)
      .frame(maxWidth: .infinity, minHeight: height)
      .background(Capsule().fill(NomiColor.primary))
      .contentShape(Capsule())
      .opacity(isEnabled ? 1 : 0.4)
  }
}

private struct NomiSecondaryButtonBody: View {
  let configuration: ButtonStyleConfiguration

  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    configuration.label
      .nomiTextStyle(.body)
      .foregroundStyle(NomiColor.navy)
      .frame(minHeight: NomiSpacing.minTarget)
      .contentShape(Rectangle())
      .opacity(isEnabled ? 1 : 0.4)
  }
}

private struct NomiHeroButtonBody: View {
  let configuration: ButtonStyleConfiguration
  let kind: NomiHeroButtonStyle.Kind

  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    switch kind {
    case .primary:
      configuration.label
        .nomiTextStyle(.button)
        .foregroundStyle(NomiHeroButtonStyle.primaryLabel)
        .padding(.horizontal, 20)
        .frame(minHeight: 52)
        .background(Capsule().fill(NomiHeroButtonStyle.primaryFill))
        .contentShape(Capsule())
        .opacity(isEnabled ? 1 : 0.4)
    case .secondary:
      configuration.label
        .nomiTextStyle(.button)
        .foregroundStyle(NomiColor.heroText)
        .padding(.horizontal, 20)
        .frame(minHeight: 52)
        .nomiGlass(.heroControl, in: Capsule())
        .contentShape(Capsule())
        .opacity(isEnabled ? 1 : 0.4)
    }
  }
}

// MARK: - Previews

#Preview("Buttons · default") {
  VStack(spacing: 16) {
    Button("Add account") {}
      .buttonStyle(NomiPrimaryButtonStyle(height: 52))
    Button("Cancel") {}
      .buttonStyle(NomiSecondaryButtonStyle())
    NomiDestructiveRow(title: "Remove account") {}
    HStack(spacing: 12) {
      NomiNavIcon(systemName: "gearshape")
      NomiHeroIcon(systemName: "gearshape")
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 8)
    .background(NomiHeroGradient.gradient(height: 120, safeTop: 54))
    Button("Done") {}
      .buttonStyle(NomiHeroButtonStyle(.primary))
    Button("Cancel") {}
      .buttonStyle(NomiHeroButtonStyle(.secondary))
  }
  .padding(20)
  .background(NomiColor.ground)
  .preferredColorScheme(.light)
}

#Preview("Buttons · AX3") {
  VStack(spacing: 16) {
    Button("Add account") {}
      .buttonStyle(NomiPrimaryButtonStyle(height: 52))
    Button("Cancel") {}
      .buttonStyle(NomiSecondaryButtonStyle())
    NomiDestructiveRow(title: "Remove account") {}
    Button("Done") {}
      .buttonStyle(NomiHeroButtonStyle(.primary))
    Button("Cancel") {}
      .buttonStyle(NomiHeroButtonStyle(.secondary))
  }
  .padding(20)
  .background(NomiColor.ground)
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.light)
}
