import Foundation
import Testing
@testable import NomiCore

struct NomiLogTests {
  private enum Sample: Error {
    case a
    case b(String)
  }

  @Test func describeNamesTypeAndCodeOnly() {
    let error = Sample.b("user@example.com")
    let line = NomiLog.describe(error)
    #expect(line.contains("Sample"))
    #expect(line.hasSuffix("#\((error as NSError).code)"))
    #expect(!line.contains("user@example.com"))
  }

  @Test func describeOfNSErrorUsesCodeNotDescription() {
    let error = NSError(
      domain: "X",
      code: 42,
      userInfo: [NSLocalizedDescriptionKey: "secret"]
    )
    let line = NomiLog.describe(error)
    #expect(line.contains("#42"))
    #expect(!line.contains("secret"))
  }

  @Test func subsystemIsTheBundleID() {
    #expect(NomiLog.subsystem == "com.shivams07.nomi")
  }
}
