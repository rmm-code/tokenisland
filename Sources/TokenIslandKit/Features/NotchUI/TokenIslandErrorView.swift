import SwiftUI

struct TokenIslandErrorView: View {
    var message: String
    var openSettings: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(TITheme.danger)
            VStack(alignment: .leading, spacing: 6) {
                Text("TokenIsland needs attention")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(TITheme.primaryText)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(TITheme.secondaryText)
                    .lineLimit(3)
            }
            Spacer()
            Button(action: openSettings) {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
