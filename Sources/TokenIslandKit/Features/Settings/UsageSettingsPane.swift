import SwiftUI

struct UsageSettingsPane: View, SettingsPaneBindingProviding {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard(title: "Usage Limits") {
                SettingsToggleRow(
                    title: "Show Usage Limits",
                    detail: "Show Claude and Codex limits. Automatic refresh never displays Keychain authentication; activating unavailable Claude usage can request access explicitly.",
                    isOn: boolBinding(\.showUsageLimitsHeader, appState: appState)
                )
                SettingsRow(
                    title: "Display Value",
                    detail: "Show consumed or remaining percentages."
                ) {
                    Picker("", selection: boolBinding(\.usageDisplayValueRemaining, appState: appState)) {
                        Text("Used").tag(false)
                        Text("Remaining").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 190)
                    .accessibilityLabel("Usage percentage display")
                }
            }

            SettingsCard(
                title: "Token usage dashboard",
                subtitle: "Full token and cost breakdowns from the legacy counter live in the dashboard window. Ingestion sources moved to Labs."
            ) {
                SettingsButtonRow(
                    title: "Open Dashboard",
                    detail: "Charts for tokens, cost, models, and projects.",
                    role: nil,
                    systemImage: "chart.bar.xaxis"
                ) {
                    AppDelegate.environment?.windowRouter.openDashboard()
                }
            }
        }
    }
}
