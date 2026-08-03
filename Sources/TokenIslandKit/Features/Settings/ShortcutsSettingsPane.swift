import SwiftUI

struct ShortcutsSettingsPane: View {
    private struct ShortcutInfo: Identifiable {
        let id = UUID()
        let action: String
        let keys: [String]
    }

    private let panelShortcuts: [ShortcutInfo] = [
        ShortcutInfo(action: "Approve", keys: ["⌃", "Y"]),
        ShortcutInfo(action: "Deny", keys: ["⌃", "N"]),
        ShortcutInfo(action: "Always Allow", keys: ["⌃", "A"]),
        ShortcutInfo(action: "Bypass Permissions", keys: ["⌃", "B"]),
        ShortcutInfo(action: "Answer Choice", keys: ["⌃", "1–9"]),
        ShortcutInfo(action: "Jump to Terminal", keys: ["⌃", "T"]),
        ShortcutInfo(action: "Collapse Panel", keys: ["esc"])
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard(
                title: "Panel Shortcuts",
                subtitle: "Active while the panel is expanded."
            ) {
                ForEach(panelShortcuts) { shortcut in
                    HStack {
                        Text(shortcut.action)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(TITheme.primaryText)
                        Spacer()
                        HStack(spacing: 4) {
                            ForEach(shortcut.keys, id: \.self) { key in
                                Text(key)
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(TITheme.primaryText)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3.5)
                                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                                    )
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            SettingsCard(title: "Session Switcher") {
                shortcutRow(action: "Next Session", keys: ["⌃", "G"])
                shortcutRow(action: "Previous Session", keys: ["⌃", "⇧", "G"])
            }

            SettingsCard(title: "Gestures") {
                HStack(spacing: 8) {
                    Image(systemName: "hand.draw")
                        .foregroundStyle(TITheme.secondaryText)
                    Text("Scroll over the notch to expand or collapse. Hover or click to open the panel.")
                        .font(.caption)
                        .foregroundStyle(TITheme.secondaryText)
                }
            }
        }
    }

    private func shortcutRow(action: String, keys: [String]) -> some View {
        HStack {
            Text(action)
                .font(.callout.weight(.medium))
                .foregroundStyle(TITheme.primaryText)
            Spacer()
            Text(keys.joined(separator: " "))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(TITheme.primaryText)
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
        }
        .padding(.vertical, 4)
    }
}
