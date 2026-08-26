import Foundation
import Testing
@testable import NomiCore

struct UPINarrationTests {
  @Test func parsesP2MSlashForm() {
    let result = UPINarration.parse("UPI/P2M/412345678901/SWIGGY/HDFC/Payment from Ph")
    #expect(result?.merchantName == "SWIGGY")
    #expect(result?.upiKindRaw == "p2m")
  }

  @Test func parsesP2PSlashForm() {
    let result = UPINarration.parse("UPI/P2P/998877665544/John Doe/ICIC/Sent to friend")
    #expect(result?.merchantName == "John Doe")
    #expect(result?.upiKindRaw == "p2p")
  }

  @Test func parsesBareVPAForm() {
    let result = UPINarration.parse("Payment to merchant@okhdfcbank via UPI")
    #expect(result?.counterpartyVPA == "merchant@okhdfcbank")
    #expect(result?.merchantName == "merchant")
  }

  @Test func parsesSBIHyphenForm() {
    let result = UPINarration.parse("UPI-AMAZON-amazon.pay@okaxis-123456789-Payment")
    #expect(result?.merchantName == "AMAZON")
    #expect(result?.counterpartyVPA == "amazon.pay@okaxis")
  }

  @Test func unmatchedInputReturnsNil() {
    let result = UPINarration.parse("NEFT TRANSFER TO SAVINGS ACCOUNT")
    #expect(result == nil)
  }
}
