import SwiftUI

struct OverviewDashboardView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                title
                metrics
                providerSplit
                liveActivity
            }
            .padding(28)
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Overview")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(TITheme.primaryText)
            Text("Live token usage across Claude, Codex, and supported local sources.")
                .font(.callout)
                .foregroundStyle(TITheme.secondaryText)
        }
    }

    private var metrics: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
            MetricCard(
                title: "Tokens Today",
                value: AppFormatters.tokens(appState.summary.totalTokensToday),
                subtitle: "\(appState.summary.recentRequests.count) recent requests",
                systemImage: "number",
                tint: TITheme.blue
            )
            MetricCard(
                title: "Estimated Cost",
                value: AppFormatters.currency(appState.summary.estimatedCostTodayUSD),
                subtitle: "Metadata-derived estimate",
                systemImage: "dollarsign.circle",
                tint: TITheme.warning
            )
            MetricCard(
                title: "Active Requests",
                value: "\(activeRequestCount)",
                subtitle: "Observed in the last minute",
                systemImage: "bolt.horizontal.circle",
                tint: .green
            )
        }
    }

    private var providerSplit: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Provider Usage")
                .font(.headline)
                .foregroundStyle(TITheme.primaryText)
            ProviderUsageRow(summary: appState.summary.provider(.claude))
            ProviderUsageRow(summary: appState.summary.provider(.gpt))
            ProviderUsageRow(summary: appState.summary.provider(.gemini))
        }
        .padding(18)
        .tiPanel()
    }

    private var liveActivity: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Live Activity")
                .font(.headline)
                .foregroundStyle(TITheme.primaryText)
            if appState.summary.recentRequests.isEmpty {
                EmptyStateView(
                    title: "Configured and idle",
                    message: "TokenIsland is ready. Usage will appear here as Claude, Codex, or the proxy emits telemetry.",
                    systemImage: "dot.radiowaves.left.and.right"
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(appState.summary.recentRequests.prefix(5)) { event in
                        RecentRequestRow(event: event)
                        if event.id != appState.summary.recentRequests.prefix(5).last?.id {
                            Divider().overlay(Color.white.opacity(0.08))
                        }
                    }
                }
                .padding(14)
                .tiPanel()
            }
        }
    }

    private var activeRequestCount: Int {
        appState.summary.providerSummaries.reduce(0) { $0 + $1.activeRequestCount }
    }
}
