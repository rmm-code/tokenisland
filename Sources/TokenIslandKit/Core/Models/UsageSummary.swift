import Foundation

struct ProviderUsageSummary: Identifiable, Hashable, Sendable {
    var id: AIProvider { provider }
    var provider: AIProvider
    var totalTokens: Int
    var percentage: Double
    var estimatedCostUSD: Decimal
    var requestCount: Int
    var activeRequestCount: Int
    var modelBreakdown: [ModelUsageSummary]
}

struct ModelUsageSummary: Identifiable, Hashable, Sendable {
    var id: String { "\(provider.rawValue)-\(model)" }
    var provider: AIProvider
    var model: String
    var totalTokens: Int
    var requestCount: Int
    var estimatedCostUSD: Decimal
}

struct ProjectUsageSummary: Identifiable, Hashable, Sendable {
    var id: String { projectPath ?? projectName }
    var projectName: String
    var projectPath: String?
    var totalTokens: Int
    var estimatedCostUSD: Decimal
}

struct HourlyUsagePoint: Identifiable, Hashable, Sendable {
    var id: Date { hour }
    var hour: Date
    var claudeTokens: Int
    var gptTokens: Int
    var geminiTokens: Int
    var unknownTokens: Int

    var totalTokens: Int {
        claudeTokens + gptTokens + geminiTokens + unknownTokens
    }
}

struct UsageSummary: Hashable, Sendable {
    var generatedAt: Date
    var totalTokensToday: Int
    var estimatedCostTodayUSD: Decimal
    var providerSummaries: [ProviderUsageSummary]
    var recentRequests: [UsageEvent]
    var hourlyTrend: [HourlyUsagePoint]
    var projects: [ProjectUsageSummary]

    static let empty = UsageSummary(
        generatedAt: Date(),
        totalTokensToday: 0,
        estimatedCostTodayUSD: 0,
        providerSummaries: AIProvider.allCases.map {
            ProviderUsageSummary(
                provider: $0,
                totalTokens: 0,
                percentage: 0,
                estimatedCostUSD: 0,
                requestCount: 0,
                activeRequestCount: 0,
                modelBreakdown: []
            )
        },
        recentRequests: [],
        hourlyTrend: [],
        projects: []
    )

    func provider(_ provider: AIProvider) -> ProviderUsageSummary {
        providerSummaries.first { $0.provider == provider }
            ?? ProviderUsageSummary(
                provider: provider,
                totalTokens: 0,
                percentage: 0,
                estimatedCostUSD: 0,
                requestCount: 0,
                activeRequestCount: 0,
                modelBreakdown: []
            )
    }
}
