import AppKit
import SwiftUI

struct SettingsCard<Content: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(TITheme.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(TITheme.secondaryText)
                }
            }
            content
        }
        .padding(18)
        .tiPanel()
    }
}

struct SettingsRow<Control: View>: View {
    var title: String
    var detail: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(TITheme.primaryText)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(TITheme.secondaryText)
            }
            Spacer(minLength: 18)
            control
        }
        .padding(.vertical, 5)
    }
}

struct SettingsToggleRow: View {
    var title: String
    var detail: String
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, detail: detail) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .accessibilityLabel(title)
        }
    }
}

struct SettingsSliderRow: View {
    var title: String
    var detail: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var valueText: (Double) -> String

    var body: some View {
        SettingsRow(title: title, detail: detail) {
            HStack(spacing: 10) {
                Slider(value: $value, in: range, step: step)
                    .frame(width: 180)
                    .accessibilityLabel(title)
                    .accessibilityValue(valueText(value))
                Text(valueText(value))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(TITheme.secondaryText)
                    .frame(width: 58, alignment: .trailing)
            }
        }
    }
}

struct SettingsSegmentedPickerRow<Value: Hashable & Identifiable & CaseIterable>: View where Value.AllCases: RandomAccessCollection, Value.AllCases.Element == Value {
    var title: String
    var detail: String
    @Binding var selection: Value
    var label: (Value) -> String

    var body: some View {
        SettingsRow(title: title, detail: detail) {
            Picker("", selection: $selection) {
                ForEach(Value.allCases) { value in
                    Text(label(value)).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 300)
            .accessibilityLabel(title)
        }
    }
}

struct SettingsButtonRow: View {
    var title: String
    var detail: String
    var role: ButtonRole?
    var systemImage: String
    var action: () -> Void

    var body: some View {
        SettingsRow(title: title, detail: detail) {
            Button(role: role, action: action) {
                Label(title, systemImage: systemImage)
            }
        }
    }
}

struct SettingsStatusRow: View {
    var title: String
    var detail: String
    var status: ServiceHealth

    var body: some View {
        SettingsRow(title: title, detail: detail) {
            StatusBadge(title: statusTitle, health: status)
        }
    }

    private var statusTitle: String {
        switch status {
        case .stopped:
            "Stopped"
        case .starting:
            "Starting"
        case .running:
            "Running"
        case .degraded:
            "Degraded"
        case .failed:
            "Failed"
        }
    }
}

struct SetupCommandBox: View {
    var command: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(command)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(TITheme.primaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}

@MainActor
protocol SettingsPaneBindingProviding {}

extension SettingsPaneBindingProviding {
    func boolBinding(_ keyPath: WritableKeyPath<AppSettings, Bool>, appState: AppState) -> Binding<Bool> {
        Binding(
            get: { appState.settings[keyPath: keyPath] },
            set: { value in appState.updateSettings { $0[keyPath: keyPath] = value } }
        )
    }

    func intBinding(_ keyPath: WritableKeyPath<AppSettings, Int>, appState: AppState, range: ClosedRange<Int>) -> Binding<Int> {
        Binding(
            get: { appState.settings[keyPath: keyPath] },
            set: { value in appState.updateSettings { $0[keyPath: keyPath] = min(max(value, range.lowerBound), range.upperBound) } }
        )
    }

    func uint16Binding(_ keyPath: WritableKeyPath<AppSettings, UInt16>, appState: AppState) -> Binding<Int> {
        Binding(
            get: { Int(appState.settings[keyPath: keyPath]) },
            set: { value in
                appState.updateSettings {
                    $0[keyPath: keyPath] = UInt16(min(max(value, 1), Int(UInt16.max)))
                }
            }
        )
    }

    func doubleBinding(_ keyPath: WritableKeyPath<AppSettings, Double>, appState: AppState, range: ClosedRange<Double>) -> Binding<Double> {
        Binding(
            get: { appState.settings[keyPath: keyPath] },
            set: { value in appState.updateSettings { $0[keyPath: keyPath] = min(max(value, range.lowerBound), range.upperBound) } }
        )
    }

    func decimalDoubleBinding(_ keyPath: WritableKeyPath<AppSettings, Decimal>, appState: AppState, range: ClosedRange<Double>) -> Binding<Double> {
        Binding(
            get: { (appState.settings[keyPath: keyPath] as NSDecimalNumber).doubleValue },
            set: { value in appState.updateSettings { $0[keyPath: keyPath] = Decimal(min(max(value, range.lowerBound), range.upperBound)) } }
        )
    }

    func enumBinding<Value: Hashable>(_ keyPath: WritableKeyPath<AppSettings, Value>, appState: AppState) -> Binding<Value> {
        Binding(
            get: { appState.settings[keyPath: keyPath] },
            set: { value in appState.updateSettings { $0[keyPath: keyPath] = value } }
        )
    }
}
