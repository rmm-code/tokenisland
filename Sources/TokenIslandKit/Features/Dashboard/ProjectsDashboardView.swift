import SwiftUI

struct ProjectsDashboardView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Projects")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(TITheme.primaryText)
                if appState.summary.projects.isEmpty {
                    EmptyStateView(
                        title: "No project attribution yet",
                        message: "When telemetry includes a workspace, repository, or project path, usage will be grouped here.",
                        systemImage: "folder.badge.questionmark"
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(appState.summary.projects) { project in
                            HStack(spacing: 12) {
                                Image(systemName: "folder")
                                    .foregroundStyle(TITheme.blue)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(project.projectName)
                                        .font(.callout.weight(.medium))
                                        .foregroundStyle(TITheme.primaryText)
                                    Text(project.projectPath ?? "Unknown path")
                                        .font(.caption)
                                        .foregroundStyle(TITheme.tertiaryText)
                                        .lineLimit(1)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(AppFormatters.tokens(project.totalTokens))
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(TITheme.primaryText)
                                    Text(AppFormatters.currency(project.estimatedCostUSD))
                                        .font(.caption)
                                        .foregroundStyle(TITheme.secondaryText)
                                }
                            }
                            .padding(12)
                            if project.id != appState.summary.projects.last?.id {
                                Divider().overlay(Color.white.opacity(0.08))
                            }
                        }
                    }
                    .tiPanel()
                }
            }
            .padding(28)
        }
    }
}
