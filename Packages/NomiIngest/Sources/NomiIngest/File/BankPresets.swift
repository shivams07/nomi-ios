import Foundation
import NomiCore

/// PROVISIONAL built-in mapping presets for the five most common Indian
/// net-banking CSV/XLSX exports (SBI, HDFC, ICICI, Axis, Kotak). These are
/// defaults, not a claim about any particular person's actual banks — a wrong
/// preset costs one manual mapping via `ColumnMappingRecord`, once, not a
/// broken import. See design §2.5 / §2.5.1.
///
/// Value Date is deliberately not mapped, and Balance is deliberately
/// ignored — both per §2.5.
struct BankPreset {
  let bankLabel: String
  let headers: [String]
  let mapping: ColumnMapping
}

enum BankPresets {
  static let all: [BankPreset] = [
    BankPreset(
      bankLabel: "SBI",
      headers: ["Txn Date", "Description", "Ref No./Cheque No.", "Value Date", "Debit", "Credit", "Balance"],
      mapping: ColumnMapping(
        dateColumn: 0,
        descriptionColumn: 1,
        amountColumn: 4,
        referenceColumn: 2,
        directionStrategy: .separateColumns(debit: 4, credit: 5),
        dateFormat: "dd MMM yyyy"
      )
    ),
    BankPreset(
      bankLabel: "HDFC",
      headers: ["Date", "Narration", "Chq./Ref.No.", "Value Dt", "Withdrawal Amt.", "Deposit Amt.", "Closing Balance"],
      mapping: ColumnMapping(
        dateColumn: 0,
        descriptionColumn: 1,
        amountColumn: 4,
        referenceColumn: 2,
        directionStrategy: .separateColumns(debit: 4, credit: 5),
        dateFormat: "dd/MM/yy"
      )
    ),
    BankPreset(
      bankLabel: "ICICI",
      headers: [
        "Transaction Date", "Transaction Remarks", "Cheque Number", "Value Date",
        "Withdrawal Amount (INR)", "Deposit Amount (INR)", "Balance (INR)",
      ],
      mapping: ColumnMapping(
        dateColumn: 0,
        descriptionColumn: 1,
        amountColumn: 4,
        referenceColumn: 2,
        directionStrategy: .separateColumns(debit: 4, credit: 5),
        dateFormat: "dd/MM/yyyy"
      )
    ),
    BankPreset(
      bankLabel: "Axis",
      headers: ["Tran Date", "PARTICULARS", "Cheque No", "Value Date", "DR", "CR", "BAL"],
      mapping: ColumnMapping(
        dateColumn: 0,
        descriptionColumn: 1,
        amountColumn: 4,
        referenceColumn: 2,
        directionStrategy: .separateColumns(debit: 4, credit: 5),
        dateFormat: "dd-MM-yyyy"
      )
    ),
    BankPreset(
      bankLabel: "Kotak",
      headers: ["Date", "Description", "Chq/Ref No", "Value Date", "Debit", "Credit", "Balance"],
      mapping: ColumnMapping(
        dateColumn: 0,
        descriptionColumn: 1,
        amountColumn: 4,
        referenceColumn: 2,
        directionStrategy: .separateColumns(debit: 4, credit: 5),
        dateFormat: "dd-MM-yyyy"
      )
    ),
  ]

  static func matching(headers: [String]) -> BankPreset? {
    let normalized = headers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    return all.first { preset in
      preset.headers.map { $0.lowercased() } == normalized
    }
  }
}
