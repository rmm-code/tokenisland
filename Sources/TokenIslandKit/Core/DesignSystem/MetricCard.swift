import SwiftUI

struct MetricCard: View {
    var title: String
    var value: String
    var subtitle: String
    var systemImage: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(TITheme.secondaryText)
                Spacer(minLength: 0)
            }
            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(TITheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(TITheme.tertiaryText)
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tiPanel()
        .accessibilityElement(children: .combine)
    }
}
