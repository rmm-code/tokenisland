import SwiftUI

/// Sidebar pages of the Settings window (blueprint §2.5, sidebar layout).
enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case integrations
    case notifications
    case display
    case sound
    case usage
    case shortcuts
    case labs
    case pass
    case about

    var id: String { rawValue }

    /// Top (untitled) sidebar group.
    static let mainPages: [SettingsSection] = [
        .general, .integrations, .notifications, .display, .sound, .usage
    ]

    /// "Advanced" sidebar group.
    static let advancedPages: [SettingsSection] = [.shortcuts, .labs]

    /// "TokenIsland" sidebar group.
    static let tokenIslandPages: [SettingsSection] = [.pass, .about]

    var title: String {
        switch self {
        case .general: "General"
        case .integrations: "Integrations"
        case .notifications: "Notifications"
        case .display: "Display"
        case .sound: "Sound"
        case .usage: "Usage"
        case .shortcuts: "Shortcuts"
        case .labs: "Labs"
        case .pass: "Pass"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .integrations: "puzzlepiece.extension.fill"
        case .notifications: "bell.badge.fill"
        case .display: "textformat.size"
        case .sound: "speaker.wave.2.fill"
        case .usage: "gauge.with.needle.fill"
        case .shortcuts: "keyboard.fill"
        case .labs: "testtube.2"
        case .pass: "wallet.pass.fill"
        case .about: "info.circle.fill"
        }
    }

    /// System Settings-style icon tile tint.
    var iconTint: Color {
        switch self {
        case .general: .gray
        case .integrations: .blue
        case .notifications: .red
        case .display: .indigo
        case .sound: .green
        case .usage: .pink
        case .shortcuts: .purple
        case .labs: .orange
        case .pass: .mint
        case .about: .blue
        }
    }

}
