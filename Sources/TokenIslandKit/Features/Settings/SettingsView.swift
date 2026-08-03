import SwiftUI

/// Sidebar-style settings window (reference layout): grouped page list on
/// the left, pane content on the right.
struct SettingsView: View {
    @State private var selection: SettingsSection = .general

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 215)
                .background(Color.white.opacity(0.035))
            Divider().overlay(Color.white.opacity(0.08))
            SettingsDetailView(section: selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(TITheme.background)
        .frame(minWidth: 780, idealWidth: 820, minHeight: 560, idealHeight: 620)
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                sidebarGroup(title: nil, pages: SettingsSection.mainPages)
                sidebarGroup(title: "Advanced", pages: SettingsSection.advancedPages)
                sidebarGroup(title: "TokenIsland", pages: SettingsSection.tokenIslandPages)
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func sidebarGroup(title: String?, pages: [SettingsSection]) -> some View {
        if let title {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(TITheme.tertiaryText)
                .padding(.top, 14)
                .padding(.horizontal, 10)
                .padding(.bottom, 2)
        }
        ForEach(pages) { page in
            Button {
                selection = page
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: page.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(page.iconTint.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Text(page.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selection == page ? TITheme.primaryText : TITheme.secondaryText)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    selection == page ? Color.white.opacity(0.12) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
