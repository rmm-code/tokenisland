import SwiftUI

/// The boarding-pass page: the onboarding "Welcome aboard" card (reused
/// directly) plus a small local-stats strip. Identity is local-only — no
/// accounts, no cloud.
struct PassSettingsPane: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Spacer()
                BoardingPassCard()
                Spacer()
            }
            .padding(.vertical, 8)

            SettingsCard(
                title: "Flight log",
                subtitle: "Local session stats for this launch."
            ) {
                HStack(spacing: 10) {
                    statTile(label: "SESSIONS NOW", value: "\(appState.sessionStore.sessions.count)")
                    statTile(label: "PET SPECIES", value: "\(PetSpecies.allCases.count)")
                    statTile(label: "TIER", value: "EXPLORER")
                }
            }
        }
    }

    private func statTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(TITheme.tertiaryText)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(TITheme.primaryText)
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
