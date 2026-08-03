import SwiftUI

struct TrendsDashboardView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Trends")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(TITheme.primaryText)
                VStack(alignment: .leading, spacing: 14) {
                    Text("Hourly Totals")
                        .font(.headline)
                        .foregroundStyle(TITheme.primaryText)
                    HourlyUsageChart(points: appState.summary.hourlyTrend)
                        .frame(height: 240)
                }
                .padding(18)
                .tiPanel()
            }
            .padding(28)
        }
    }
}

struct HourlyUsageChart: View {
    var points: [HourlyUsagePoint]

    var body: some View {
        GeometryReader { proxy in
            let maxValue = max(points.map(\.totalTokens).max() ?? 1, 1)
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(points) { point in
                    VStack(spacing: 5) {
                        ZStack(alignment: .bottom) {
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                            VStack(spacing: 0) {
                                segment(tokens: point.unknownTokens, maxValue: maxValue, height: proxy.size.height - 28, color: AIProvider.unknown.tint)
                                segment(tokens: point.geminiTokens, maxValue: maxValue, height: proxy.size.height - 28, color: AIProvider.gemini.tint)
                                segment(tokens: point.gptTokens, maxValue: maxValue, height: proxy.size.height - 28, color: AIProvider.gpt.tint)
                                segment(tokens: point.claudeTokens, maxValue: maxValue, height: proxy.size.height - 28, color: AIProvider.claude.tint)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        Text(hourLabel(point.hour))
                            .font(.system(size: 9))
                            .foregroundStyle(TITheme.tertiaryText)
                    }
                }
            }
        }
        .accessibilityLabel("Hourly token usage chart")
    }

    private func segment(tokens: Int, maxValue: Int, height: CGFloat, color: Color) -> some View {
        Rectangle()
            .fill(color)
            .frame(height: max(tokens > 0 ? 2 : 0, CGFloat(tokens) / CGFloat(maxValue) * height))
    }

    private func hourLabel(_ date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        return hour % 6 == 0 ? "\(hour)" : ""
    }
}
