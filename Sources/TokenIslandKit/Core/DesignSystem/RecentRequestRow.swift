import SwiftUI

struct RecentRequestRow: View {
    var event: UsageEvent

    var body: some View {
        HStack(spacing: 12) {
            ProviderIconView(provider: event.provider, size: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(ModelNameFormatter.displayName(event.model) ?? event.model)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(TITheme.primaryText)
                        .lineLimit(1)
                    Text(event.sourceApp)
                        .font(.caption)
                        .foregroundStyle(TITheme.tertiaryText)
                        .lineLimit(1)
                }
                HStack(spacing: 10) {
                    Text("\(AppFormatters.tokens(event.inputTokens)) in")
                    Text("\(AppFormatters.tokens(event.outputTokens)) out")
                    if event.cacheReadTokens + event.cacheWriteTokens > 0 {
                        Text("\(AppFormatters.tokens(event.cacheReadTokens + event.cacheWriteTokens)) cache")
                    }
                    Text(AppFormatters.compactDuration(milliseconds: event.latencyMS))
                }
                .font(.caption2)
                .foregroundStyle(TITheme.secondaryText)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(event.estimatedCostUSD > 0 ? AppFormatters.currency(event.estimatedCostUSD) : "Cost unavailable")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TITheme.primaryText)
                Text(AppFormatters.timeFormatter.string(from: event.timestamp))
                    .font(.caption2)
                    .foregroundStyle(TITheme.tertiaryText)
            }
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}
