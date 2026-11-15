import Foundation

/// Pure logic behind `AboutScreen` and `LicensesScreen` (S9b).
enum AboutLogic {
  /// One row in the About card's list, in display order.
  enum Row: Equatable {
    case privacyPolicy
    case termsOfUse
    case support
    case licences
  }

  /// "Version <short> (<build>)" from the bundle's Info dictionary. Both keys
  /// are needed; without them (previews, `swift test`) the module version stands in.
  static func versionLine(bundle: Bundle) -> String {
    let info = bundle.infoDictionary
    guard let short = info?["CFBundleShortVersionString"] as? String,
          let build = info?["CFBundleVersion"] as? String
    else {
      return "Version \(NomiUIModule.version)"
    }
    return "Version \(short) (\(build))"
  }

  /// The rows the About card shows. The policy and terms rows appear only when
  /// their URL is set; support and licences always show.
  static func visibleRows(privacy: URL?, terms: URL?) -> [Row] {
    var rows: [Row] = []
    if privacy != nil { rows.append(.privacyPolicy) }
    if terms != nil { rows.append(.termsOfUse) }
    rows.append(.support)
    rows.append(.licences)
    return rows
  }

  /// "© <year> <publisher>", or nil when there is no publisher name to print.
  static func footer(publisherName: String?, year: Int) -> String? {
    guard let name = publisherName?.trimmingCharacters(in: .whitespacesAndNewlines),
          !name.isEmpty
    else {
      return nil
    }
    return "© \(year) \(name)"
  }

  static func mailtoURL(address: String) -> URL? {
    URL(string: "mailto:\(address)")
  }

  /// The bundled Licenses.txt, or nil when the resource cannot be read. The
  /// screen shows a plain sentence in that case rather than an empty page.
  static func licencesText() -> String? {
    guard let url = Bundle.module.url(forResource: "Licenses", withExtension: "txt"),
          let text = try? String(contentsOf: url, encoding: .utf8),
          !text.isEmpty
    else {
      return nil
    }
    return text
  }
}
