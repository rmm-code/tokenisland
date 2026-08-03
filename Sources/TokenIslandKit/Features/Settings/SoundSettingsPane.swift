import SwiftUI

struct SoundSettingsPane: View, SettingsPaneBindingProviding {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard(title: "Output") {
                SettingsToggleRow(
                    title: "Enable Sound Effects",
                    detail: "8-bit cues synthesized in-app — no audio files.",
                    isOn: boolBinding(\.soundEnabled, appState: appState)
                )
                SettingsRow(
                    title: "Sound pack",
                    detail: "Chip is the classic square wave; Soft rounds it off; Arcade is brighter with a fast arpeggio snap."
                ) {
                    Picker("", selection: soundPackBinding) {
                        ForEach(SoundPack.allCases) { pack in
                            Text(pack.displayName).tag(pack)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                    .accessibilityLabel("Sound pack")
                }
                SettingsSliderRow(
                    title: "Volume",
                    detail: "Relative to system output volume.",
                    value: doubleBinding(\.soundVolume, appState: appState, range: 0...1),
                    range: 0...1,
                    step: 0.05,
                    valueText: { "\(Int($0 * 100))%" }
                )
            }

            SettingsCard(title: "Session") {
                soundRow(title: "Session Start", detail: "A new monitored agent session appears.", keyPath: \.soundSessionStart, event: .sessionStart)
                soundRow(title: "Task Complete", detail: "AI finished its turn.", keyPath: \.soundTaskComplete, event: .taskComplete)
                soundRow(title: "Task Error", detail: "Tool failure or API error.", keyPath: \.soundTaskError, event: .taskError)
            }

            SettingsCard(title: "Interactions") {
                soundRow(title: "Approval Needed", detail: "Permission or question pending.", keyPath: \.soundApprovalNeeded, event: .approvalNeeded)
                soundRow(title: "Task Acknowledge", detail: "You submitted a prompt.", keyPath: \.soundTaskAcknowledge, event: .taskAcknowledge)
            }

            SettingsCard(title: "System") {
                soundRow(title: "Context Limit", detail: "Context window almost full.", keyPath: \.soundContextLimit, event: .contextLimit)
                soundRow(title: "Idle Reminder", detail: "AI is waiting for your input.", keyPath: \.soundIdleReminder, event: .idleReminder)
            }
        }
    }

    private func soundRow(
        title: String,
        detail: String,
        keyPath: WritableKeyPath<AppSettings, Bool>,
        event: SoundEvent
    ) -> some View {
        SettingsRow(title: title, detail: detail) {
            HStack(spacing: 10) {
                Button {
                    SoundBank.shared.preview(
                        event,
                        volume: appState.settings.soundVolume,
                        pack: SoundPack.named(appState.settings.soundPack)
                    )
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(TITheme.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Preview \(title) sound")
                Toggle("", isOn: boolBinding(keyPath, appState: appState))
                    .labelsHidden()
                    .accessibilityLabel("Enable \(title) sound")
            }
        }
    }

    private var soundPackBinding: Binding<SoundPack> {
        Binding(
            get: { SoundPack.named(appState.settings.soundPack) },
            set: { pack in appState.updateSettings { $0.soundPack = pack.rawValue } }
        )
    }
}
