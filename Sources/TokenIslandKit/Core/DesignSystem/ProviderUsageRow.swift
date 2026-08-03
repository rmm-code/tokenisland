import SwiftUI

struct ProviderUsageRow: View {
    var summary: ProviderUsageSummary
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ProviderIconView(provider: summary.provider, size: compact ? 24 : 32)
            VStack(alignment: .leading, spacing: compact ? 5 : 7) {
                HStack {
                    Text(summary.provider.displayName)
                        .font(compact ? .caption.weight(.semibold) : .callout.weight(.semibold))
                        .foregroundStyle(TITheme.primaryText)
                    Spacer(minLength: 8)
                    Text(AppFormatters.percent(summary.percentage))
                        .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                        .foregroundStyle(summary.provider.tint)
                }
                TokenProgressBar(value: summary.percentage, tint: summary.provider.tint, height: compact ? 3 : 4)
                HStack {
                    Text("\(AppFormatters.tokens(summary.totalTokens)) tokens today")
                    Spacer()
                    Text(AppFormatters.currency(summary.estimatedCostUSD))
                }
                .font(.caption2)
                .foregroundStyle(TITheme.tertiaryText)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(summary.provider.displayName), \(AppFormatters.percent(summary.percentage)), \(AppFormatters.tokens(summary.totalTokens)) tokens today")
    }
}
