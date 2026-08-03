import Foundation

enum PreviewData {
    static let events: [UsageEvent] = [
        UsageEvent(
            timestamp: Date().addingTimeInterval(-120),
            provider: .claude,
            sourceApp: "Claude Code",
            projectName: "TokenIsland",
            projectPath: "/Users/example/TokenIsland",
            model: "claude-3-5-sonnet",
            inputTokens: 18_400,
            outputTokens: 5_200,
            cacheReadTokens: 44_000,
            estimatedCostUSD: 0.18,
            requestID: "preview-claude-1",
            latencyMS: 1420,
            sessionID: "preview"
        ),
        UsageEvent(
            timestamp: Date().addingTimeInterval(-520),
            provider: .gpt,
            sourceApp: "Codex CLI",
            projectName: "TokenIsland",
            projectPath: "/Users/example/TokenIsland",
            model: "gpt-4.1",
            inputTokens: 10_500,
            outputTokens: 3_900,
            estimatedCostUSD: 0.09,
            requestID: "preview-gpt-1",
            latencyMS: 980,
            sessionID: "preview"
        )
    ]

    static let summary = UsageAggregator().makeSummary(
        events: events,
        recentRequests: events,
        now: Date(),
        calendar: .current
    )
}
