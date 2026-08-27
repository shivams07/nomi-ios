import NomiCore
import SwiftUI

/// Card 6: one row per account. The caller is responsible for archived
/// exclusion — `DashboardView` calls `accountSummaries(includeArchived:
/// false)` — this view has no opinion on archival, it just renders whatever
/// summaries it is handed.
public struct AccountsCard: View {
  public let accounts: [AccountSummary]

  public init(accounts: [AccountSummary]) {
    self.accounts = accounts
  }

  public var body: some View {
    DashboardCard {
      VStack(alignment: .leading, spacing: NomiSpacing.sm) {
        Text("Accounts")
          .nomiTextStyle(.title)
          .foregroundStyle(NomiColor.textPrimary)
        if accounts.isEmpty {
          Text("No accounts yet")
            .nomiTextStyle(.caption)
            .foregroundStyle(NomiColor.textTertiary)
        } else {
          VStack(spacing: NomiSpacing.xs) {
            ForEach(accounts) { account in
              HStack(spacing: NomiSpacing.xs) {
                VStack(alignment: .leading, spacing: 2) {
                  Text(account.displayName)
                    .nomiTextStyle(.body)
                    .foregroundStyle(NomiColor.textPrimary)
                    .lineLimit(1)
                  Text(account.institution)
                    .nomiTextStyle(.caption)
                    .foregroundStyle(NomiColor.textTertiary)
                    .lineLimit(1)
                }
                Spacer(minLength: NomiSpacing.xs)
                Text(NomiFormatters.amountString(minor: account.trackedBalanceMinor))
                  .font(TabularFigures.font(name: NomiFont.montserratMedium, size: 14))
                  .foregroundStyle(NomiColor.textSecondary)
              }
            }
          }
        }
      }
    }
  }
}

#Preview("Accounts — default, dark") {
  AccountsCard(accounts: [
    AccountSummary(id: UUID(), displayName: "HDFC •• 4471", institution: "HDFC Bank", lastFour: "4471", kindRaw: "bank", trackedBalanceMinor: 128_450_00, transactionCount: 42, trackingSince: Date(), isArchived: false),
    AccountSummary(id: UUID(), displayName: "ICICI •• 8890", institution: "ICICI Bank", lastFour: "8890", kindRaw: "bank", trackedBalanceMinor: -4_200_00, transactionCount: 11, trackingSince: Date(), isArchived: false),
  ])
  .padding()
  .background(NomiColor.surfaceCanvas)
  .preferredColorScheme(.dark)
}

#Preview("Accounts — empty, dark") {
  AccountsCard(accounts: [])
    .padding()
    .background(NomiColor.surfaceCanvas)
    .preferredColorScheme(.dark)
}

#Preview("Accounts — accessibility 3, dark") {
  AccountsCard(accounts: [
    AccountSummary(id: UUID(), displayName: "HDFC •• 4471", institution: "HDFC Bank", lastFour: "4471", kindRaw: "bank", trackedBalanceMinor: 128_450_00, transactionCount: 42, trackingSince: Date(), isArchived: false),
  ])
  .padding()
  .background(NomiColor.surfaceCanvas)
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.dark)
}
