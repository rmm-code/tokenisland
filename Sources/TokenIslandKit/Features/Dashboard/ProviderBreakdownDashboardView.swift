import SwiftUI

struct ProviderBreakdownDashboardView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Provider Breakdown")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(TITheme.primaryText)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    providerCard(appState.summary.provider(.claude))
                    providerCard(appState.summary.provider(.gpt))
                    providerCard(appState.summary.provider(.gemini))
                }
                unknownUsage
            }
            .padding(28)
        }
    }

    private func providerCard(_ summary: ProviderUsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ProviderUsageRow(summary: summary)
            Divider().overlay(Color.white.opacity(0.08))
            Text("Models")
                .font(.caption.weight(.semibold))
                .foregroundStyle(TITheme.secondaryText)
            if summary.modelBreakdown.isEmpty {
                Text("No model data yet")
                    .font(.callout)
                    .foregroundStyle(TITheme.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(summary.modelBreakdown.prefix(8)) { model in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ModelNameFormatter.displayName(model.model) ?? model.model)
                                .font(.callout.weight(.medium))
                                .foregroundStyle(TITheme.primaryText)
                            Text("\(model.requestCount) requests")
                                .font(.caption2)
                                .foregroundStyle(TITheme.tertiaryText)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(AppFormatters.tokens(model.totalTokens))
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(TITheme.primaryText)
                            Text(
                                model.estimatedCostUSD > 0
                                    ? AppFormatters.currency(model.estimatedCostUSD)
                                    : "Cost unavailable"
                            )
                                .font(.caption2)
                                .foregroundStyle(TITheme.secondaryText)
                        }
                    }
                    .padding(.vertical, 5)
                }
            }
        }
        .padding(18)
        .tiPanel()
    }

    private var unknownUsage: some View {
        let summary = appState.summary.provider(.unknown)
        return Group {
            if summary.totalTokens > 0 {
                providerCard(summary)
            }
        }
    }
}
