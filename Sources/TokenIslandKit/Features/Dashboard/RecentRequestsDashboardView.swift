import SwiftUI

struct RecentRequestsDashboardView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Recent Requests")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(TITheme.primaryText)
                if appState.summary.recentRequests.isEmpty {
                    EmptyStateView(
                        title: "No requests captured",
                        message: "Enable Claude Code OTLP, Codex telemetry, or the OpenAI-compatible proxy to populate this stream.",
                        systemImage: "tray"
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(appState.summary.recentRequests) { event in
                            RecentRequestRow(event: event)
                                .padding(.horizontal, 12)
                            if event.id != appState.summary.recentRequests.last?.id {
                                Divider().overlay(Color.white.opacity(0.08))
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .tiPanel()
                }
            }
            .padding(28)
        }
    }
}
