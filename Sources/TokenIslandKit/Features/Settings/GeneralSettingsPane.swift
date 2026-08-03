import SwiftUI

struct GeneralSettingsPane: View, SettingsPaneBindingProviding {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard(title: "System") {
                SettingsToggleRow(
                    title: "Launch at Login",
                    detail: "Start automatically when you log in.",
                    isOn: boolBinding(\.launchAtLogin, appState: appState)
                )
            }

            SettingsCard(title: "Expansion") {
                SettingsToggleRow(
                    title: "Expand notch on hover",
                    detail: "Open the full session panel when the pointer rests on the notch.",
                    isOn: boolBinding(\.expandOnHover, appState: appState)
                )
                SettingsSliderRow(
                    title: "Hover duration",
                    detail: "Delay before the hover peek opens.",
                    value: hoverSecondsBinding,
                    range: 0.05...0.6,
                    step: 0.05,
                    valueText: { String(format: "%.2fs", $0) }
                )
                SettingsToggleRow(
                    title: "Smart suppression",
                    detail: "Don't reveal completions while the agent's terminal app is frontmost.",
                    isOn: boolBinding(\.smartSuppression, appState: appState)
                )
            }

            SettingsCard(title: "Visibility") {
                SettingsSegmentedPickerRow(
                    title: "Show in fullscreen",
                    detail: "When fullscreen apps are frontmost.",
                    selection: enumBinding(\.fullscreenOverlayMode, appState: appState),
                    label: \.displayName
                )
                SettingsToggleRow(
                    title: "Auto-hide when no active sessions",
                    detail: "The strip disappears entirely while nothing is running.",
                    isOn: boolBinding(\.autoHideWhenNoSessions, appState: appState)
                )
            }

            SettingsCard(title: "Dismissal") {
                SettingsToggleRow(
                    title: "Auto-collapse on mouse leave",
                    detail: "Close the panel when the pointer leaves it.",
                    isOn: autoCollapseBinding
                )
                SettingsSliderRow(
                    title: "Auto reveal dwell",
                    detail: "How long completion and warning reveals stay open. ESC closes sooner.",
                    value: doubleBinding(\.autoRevealDwellSeconds, appState: appState, range: 2...15),
                    range: 2...15,
                    step: 1,
                    valueText: { "\(Int($0))s" }
                )
                SettingsToggleRow(
                    title: "Dismiss auto reveal on outside click",
                    detail: "Clicking anywhere outside the panel closes reveals immediately.",
                    isOn: boolBinding(\.dismissRevealOnOutsideClick, appState: appState)
                )
                SettingsRow(
                    title: "Idle session cleanup",
                    detail: "Applies only to sessions without a clear close signal."
                ) {
                    Picker("", selection: idleCleanupBinding) {
                        Text("1 hour").tag(1.0)
                        Text("2 hours (default)").tag(2.0)
                        Text("4 hours").tag(4.0)
                        Text("8 hours").tag(8.0)
                    }
                    .labelsHidden()
                    .frame(width: 170)
                    .accessibilityLabel("Idle session cleanup")
                }
            }

            SettingsCard(title: "Interaction") {
                SettingsToggleRow(
                    title: "Disable click-to-jump",
                    detail: "When enabled, clicking a session won't switch to its terminal or IDE.",
                    isOn: boolBinding(\.disableClickToJump, appState: appState)
                )
                SettingsButtonRow(
                    title: "Reset all settings",
                    detail: "Restore every option to its default value.",
                    role: .destructive,
                    systemImage: "arrow.counterclockwise"
                ) {
                    appState.resetSettings()
                }
            }
        }
    }

    private var hoverSecondsBinding: Binding<Double> {
        Binding(
            get: { Double(appState.settings.hoverOpenDelayMS) / 1000 },
            set: { value in appState.updateSettings { $0.hoverOpenDelayMS = Int(value * 1000) } }
        )
    }

    private var autoCollapseBinding: Binding<Bool> {
        Binding(
            get: { !appState.settings.preventCloseOnMouseLeave },
            set: { value in appState.updateSettings { $0.preventCloseOnMouseLeave = !value } }
        )
    }

    private var idleCleanupBinding: Binding<Double> {
        Binding(
            get: { appState.settings.idleCleanupHours },
            set: { value in appState.updateSettings { $0.idleCleanupHours = value } }
        )
    }
}
