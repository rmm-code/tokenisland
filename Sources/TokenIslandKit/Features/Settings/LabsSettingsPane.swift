import SwiftUI

struct LabsSettingsPane: View, SettingsPaneBindingProviding {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard(title: "Claude Code") {
                SettingsToggleRow(
                    title: "Use Native Claude Code Approvals",
                    detail: "Skip TokenIsland approval cards; let Claude Code handle approvals in the terminal.",
                    isOn: boolBinding(\.useNativeClaudeApprovals, appState: appState)
                )
                SettingsSliderRow(
                    title: "Approval hold timeout",
                    detail: "How long a tool call waits for your verdict before falling back to the terminal prompt.",
                    value: doubleBinding(\.approvalHoldSeconds, appState: appState, range: 10...85),
                    range: 10...85,
                    step: 5,
                    valueText: { "\(Int($0))s" }
                )
            }

            SettingsCard(
                title: "Legacy usage sources",
                subtitle: "Optional local ingestion. Off by default; session monitoring does not need it."
            ) {
                SettingsToggleRow(
                    title: "OTLP receiver",
                    detail: "Accept OpenTelemetry JSON from Claude Code exporters.",
                    isOn: boolBinding(\.enableOTLPReceiver, appState: appState)
                )
                SettingsRow(
                    title: "OTLP port",
                    detail: "Default 4318."
                ) {
                    TextField("", value: uint16Binding(\.otlpPort, appState: appState), formatter: NumberFormatter())
                        .frame(width: 84)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("OTLP port")
                }
                if appState.settings.enableOTLPReceiver {
                    SetupCommandBox(command: """
                    export CLAUDE_CODE_ENABLE_TELEMETRY=1
                    export OTEL_METRICS_EXPORTER=otlp
                    export OTEL_EXPORTER_OTLP_PROTOCOL=http/json
                    export OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:\(appState.settings.otlpPort)
                    """)
                }
                SettingsToggleRow(
                    title: "OpenAI-compatible proxy",
                    detail: "Forwarding proxy that counts usage from responses.",
                    isOn: boolBinding(\.enableOpenAIProxy, appState: appState)
                )
            }
        }
    }
}
