import SwiftUI

struct EmptyStateView: View {
    var title: String
    var message: String
    var systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(TITheme.blue)
            Text(title)
                .font(.headline)
                .foregroundStyle(TITheme.primaryText)
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(TITheme.secondaryText)
                .frame(maxWidth: 360)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .tiPanel()
        .accessibilityElement(children: .combine)
    }
}
