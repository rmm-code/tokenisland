import SwiftUI

struct DisplaySettingsPane: View, SettingsPaneBindingProviding {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard(title: "Notch") {
                NotchPreviewView(settings: appState.settings)
                SettingsRow(
                    title: "Strip mode",
                    detail: "Clean keeps just pets and count; Detailed adds session status at a glance."
                ) {
                    Picker("", selection: detailedModeBinding) {
                        Text("Clean").tag(false)
                        Text("Detailed").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 200)
                    .accessibilityLabel("Strip mode")
                }
                SettingsRow(
                    title: "Display",
                    detail: "Which screen hosts the island."
                ) {
                    Picker("", selection: displayTargetBinding) {
                        Text("Built-in Retina Display").tag("builtin")
                        Text("Main Display").tag("main")
                        Text("Pointer Display").tag("focus")
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 200)
                    .accessibilityLabel("Notch display")
                }
            }

            SettingsCard(title: "Panel size") {
                SettingsSliderRow(
                    title: "Content Font Size",
                    detail: "Base size for session card text.",
                    value: doubleBinding(\.contentFontSize, appState: appState, range: 9...14),
                    range: 9...14,
                    step: 0.5,
                    valueText: { String(format: "%.1fpt", $0) }
                )
                SettingsSliderRow(
                    title: "Completion Card Height",
                    detail: "Height budget for the completion excerpt.",
                    value: doubleBinding(\.completionCardHeight, appState: appState, range: 60...140),
                    range: 60...140,
                    step: 5,
                    valueText: { "\(Int($0))pt" }
                )
                SettingsSliderRow(
                    title: "Max Panel Height",
                    detail: "Upper bound for the expanded panel.",
                    value: doubleBinding(\.maxPanelHeight, appState: appState, range: 300...700),
                    range: 300...700,
                    step: 20,
                    valueText: { "\(Int($0))pt" }
                )
                SettingsSliderRow(
                    title: "Max Panel Width",
                    detail: "Upper bound for the expanded panel.",
                    value: doubleBinding(\.maxPanelWidth, appState: appState, range: 440...900),
                    range: 440...900,
                    step: 20,
                    valueText: { "\(Int($0))pt" }
                )
            }

            SettingsCard(title: "Session card") {
                SettingsToggleRow(
                    title: "Show Project Name",
                    detail: "Prefix the card title with the project folder.",
                    isOn: boolBinding(\.showProjectName, appState: appState)
                )
                SettingsToggleRow(
                    title: "Show Worktree",
                    detail: "Show the git worktree when the session runs in one.",
                    isOn: boolBinding(\.showWorktree, appState: appState)
                )
                SettingsToggleRow(
                    title: "Show AI Model",
                    detail: "Display the model chip on cards.",
                    isOn: boolBinding(\.showAIModel, appState: appState)
                )
                SettingsToggleRow(
                    title: "Show Subagents",
                    detail: "Display active fan-out Task agents under their main session.",
                    isOn: boolBinding(\.showSubagents, appState: appState)
                )
                SettingsToggleRow(
                    title: "Show Agent Activity Detail",
                    detail: "Live tool call line (Read src/… ) under the title.",
                    isOn: boolBinding(\.showAgentActivityDetail, appState: appState)
                )
            }

            SettingsCard(title: "Appearance") {
                SettingsSliderRow(
                    title: "Animation speed",
                    detail: "Spring speed for open/close transitions.",
                    value: doubleBinding(\.animationSpeed, appState: appState, range: 0.45...1.8),
                    range: 0.45...1.8,
                    step: 0.05,
                    valueText: { String(format: "%.2fx", $0) }
                )
                SettingsSliderRow(
                    title: "Corner radius",
                    detail: "Bottom corner rounding of the island.",
                    value: doubleBinding(\.islandCornerRadius, appState: appState, range: 14...40),
                    range: 14...40,
                    step: 1,
                    valueText: { "\(Int($0))pt" }
                )
                SettingsSliderRow(
                    title: "Shadow intensity",
                    detail: "Drop shadow under the expanded island.",
                    value: doubleBinding(\.shadowIntensity, appState: appState, range: 0...1),
                    range: 0...1,
                    step: 0.05,
                    valueText: { String(format: "%.2f", $0) }
                )
            }

            SettingsCard(
                title: "Tuning",
                subtitle: "Fine-tune notch dimensions if your machine doesn't fit perfectly. 0 uses the macOS API value."
            ) {
                SettingsSliderRow(
                    title: "Notch width",
                    detail: "Adjustment applied to the detected notch width.",
                    value: doubleBinding(\.notchWidthAdjustment, appState: appState, range: -40...40),
                    range: -40...40,
                    step: 2,
                    valueText: { "\(Int($0))pt" }
                )
                SettingsSliderRow(
                    title: "Notch height",
                    detail: "Adjustment applied to the detected notch height.",
                    value: doubleBinding(\.notchHeightAdjustment, appState: appState, range: -20...20),
                    range: -20...20,
                    step: 1,
                    valueText: { "\(Int($0))pt" }
                )
            }
        }
    }

    private var detailedModeBinding: Binding<Bool> {
        boolBinding(\.notchDetailedMode, appState: appState)
    }

    private var displayTargetBinding: Binding<String> {
        Binding(
            get: { appState.settings.displayTarget },
            set: { value in appState.updateSettings { $0.displayTarget = value } }
        )
    }

}
