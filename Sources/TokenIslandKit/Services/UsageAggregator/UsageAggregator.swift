import Foundation

struct UsageAggregator {
    func makeSummary(
        events: [UsageEvent],
        recentRequests: [UsageEvent],
        now: Date,
        calendar: Calendar
    ) -> UsageSummary {
        let totalTokens = events.reduce(0) { $0 + $1.totalTokens }
        let totalCost = events.reduce(Decimal(0)) { $0 + $1.estimatedCostUSD }
        let eventsByProvider = Dictionary(grouping: events, by: \.provider)

        let providerSummaries = AIProvider.allCases.map { provider in
            let providerEvents = eventsByProvider[provider, default: []]
            let providerTokens = providerEvents.reduce(0) { $0 + $1.totalTokens }
            let providerCost = providerEvents.reduce(Decimal(0)) { $0 + $1.estimatedCostUSD }
            let activeRequests = providerEvents.filter { now.timeIntervalSince($0.timestamp) <= 60 }.count
            return ProviderUsageSummary(
                provider: provider,
                totalTokens: providerTokens,
                percentage: totalTokens > 0 ? Double(providerTokens) / Double(totalTokens) : 0,
                estimatedCostUSD: providerCost,
                requestCount: providerEvents.count,
                activeRequestCount: activeRequests,
                modelBreakdown: modelBreakdown(provider: provider, events: providerEvents)
            )
        }

        return UsageSummary(
            generatedAt: now,
            totalTokensToday: totalTokens,
            estimatedCostTodayUSD: totalCost,
            providerSummaries: providerSummaries,
            recentRequests: recentRequests,
            hourlyTrend: hourlyTrend(events: events, now: now, calendar: calendar),
            projects: projectBreakdown(events: events)
        )
    }

    private func modelBreakdown(provider: AIProvider, events: [UsageEvent]) -> [ModelUsageSummary] {
        Dictionary(grouping: events, by: \.model)
            .map { model, modelEvents in
                ModelUsageSummary(
                    provider: provider,
                    model: model,
                    totalTokens: modelEvents.reduce(0) { $0 + $1.totalTokens },
                    requestCount: modelEvents.count,
                    estimatedCostUSD: modelEvents.reduce(Decimal(0)) { $0 + $1.estimatedCostUSD }
                )
            }
            .sorted { $0.totalTokens > $1.totalTokens }
    }

    private func hourlyTrend(events: [UsageEvent], now: Date, calendar: Calendar) -> [HourlyUsagePoint] {
        let startOfCurrentHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let hours = (0..<24).compactMap {
            calendar.date(byAdding: .hour, value: -23 + $0, to: startOfCurrentHour)
        }
        let grouped = Dictionary(grouping: events) { event in
            calendar.dateInterval(of: .hour, for: event.timestamp)?.start ?? event.timestamp
        }

        return hours.map { hour in
            let hourEvents = grouped[hour, default: []]
            return HourlyUsagePoint(
                hour: hour,
                claudeTokens: hourEvents.filter { $0.provider == .claude }.reduce(0) { $0 + $1.totalTokens },
                gptTokens: hourEvents.filter { $0.provider == .gpt }.reduce(0) { $0 + $1.totalTokens },
                geminiTokens: hourEvents.filter { $0.provider == .gemini }.reduce(0) { $0 + $1.totalTokens },
                unknownTokens: hourEvents.filter { $0.provider == .unknown }.reduce(0) { $0 + $1.totalTokens }
            )
        }
    }

    private func projectBreakdown(events: [UsageEvent]) -> [ProjectUsageSummary] {
        let keyed = Dictionary(grouping: events) { event in
            event.projectPath ?? event.projectName ?? "Unknown Project"
        }

        return keyed.map { key, projectEvents in
            let first = projectEvents.first
            return ProjectUsageSummary(
                projectName: first?.projectName ?? URL(fileURLWithPath: key).lastPathComponent,
                projectPath: first?.projectPath,
                totalTokens: projectEvents.reduce(0) { $0 + $1.totalTokens },
                estimatedCostUSD: projectEvents.reduce(Decimal(0)) { $0 + $1.estimatedCostUSD }
            )
        }
        .sorted { $0.totalTokens > $1.totalTokens }
    }
}
