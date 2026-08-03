import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selection: DashboardSection? = .overview

    var body: some View {
        NavigationSplitView {
            List(DashboardSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section as DashboardSection?)
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(TITheme.background)
        }
        .toolbar {
            ToolbarItemGroup {
                StatusBadge(title: "OTLP", health: appState.ingestionStatus.otlpHealth)
                StatusBadge(title: "Proxy", health: appState.ingestionStatus.proxyHealth)
                Button {
                    Task { await appState.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection ?? .overview {
        case .overview:
            OverviewDashboardView()
        case .providers:
            ProviderBreakdownDashboardView()
        case .recent:
            RecentRequestsDashboardView()
        case .trends:
            TrendsDashboardView()
        case .projects:
            ProjectsDashboardView()
        }
    }
}
