import SwiftUI

struct SettingsDetailView: View {
    var section: SettingsSection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: section.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(section.iconTint.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    Text(section.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(TITheme.primaryText)
                }
                .padding(.bottom, 2)

                pane
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var pane: some View {
        switch section {
        case .general: GeneralSettingsPane()
        case .integrations: IntegrationsSettingsPane()
        case .notifications: NotificationsSettingsPane()
        case .display: DisplaySettingsPane()
        case .sound: SoundSettingsPane()
        case .usage: UsageSettingsPane()
        case .shortcuts: ShortcutsSettingsPane()
        case .labs: LabsSettingsPane()
        case .pass: PassSettingsPane()
        case .about: AboutSettingsPane()
        }
    }
}
