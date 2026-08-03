import Foundation

struct TokenCostEstimator {
    struct Rate: Sendable {
        var inputPerMillion: Decimal
        var outputPerMillion: Decimal
        var cacheReadPerMillion: Decimal
        var cacheWritePerMillion: Decimal
    }

    private let defaultClaude = Rate(
        inputPerMillion: 3,
        outputPerMillion: 15,
        cacheReadPerMillion: 0.30,
        cacheWritePerMillion: 3.75
    )
    func estimate(
        provider: AIProvider,
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int,
        cacheWriteTokens: Int
    ) -> Decimal {
        let rate = rate(for: provider, model: model)
        let million = Decimal(1_000_000)
        return Decimal(inputTokens) / million * rate.inputPerMillion
            + Decimal(outputTokens) / million * rate.outputPerMillion
            + Decimal(cacheReadTokens) / million * rate.cacheReadPerMillion
            + Decimal(cacheWriteTokens) / million * rate.cacheWritePerMillion
    }

    private func rate(for provider: AIProvider, model: String) -> Rate {
        let normalized = model.lowercased()
        switch provider {
        case .claude:
            if normalized.contains("fable-5") || normalized.contains("mythos-5") {
                return Rate(inputPerMillion: 10, outputPerMillion: 50, cacheReadPerMillion: 1, cacheWritePerMillion: 12.50)
            }
            if normalized.contains("opus-4-8") {
                return Rate(inputPerMillion: 5, outputPerMillion: 25, cacheReadPerMillion: 0.50, cacheWritePerMillion: 6.25)
            }
            if normalized.contains("sonnet-5") {
                return Rate(inputPerMillion: 2, outputPerMillion: 10, cacheReadPerMillion: 0.20, cacheWritePerMillion: 2.50)
            }
            if normalized.contains("haiku-4-5") {
                return Rate(inputPerMillion: 1, outputPerMillion: 5, cacheReadPerMillion: 0.10, cacheWritePerMillion: 1.25)
            }
            if normalized.contains("haiku") {
                return Rate(inputPerMillion: 0.80, outputPerMillion: 4, cacheReadPerMillion: 0.08, cacheWritePerMillion: 1)
            }
            if normalized.contains("opus") {
                return Rate(inputPerMillion: 15, outputPerMillion: 75, cacheReadPerMillion: 1.50, cacheWritePerMillion: 18.75)
            }
            return defaultClaude
        case .gpt:
            if normalized.contains("gpt-5.5-pro") || normalized.contains("gpt-5.4-pro") {
                return Rate(inputPerMillion: 30, outputPerMillion: 180, cacheReadPerMillion: 0, cacheWritePerMillion: 37.50)
            }
            if normalized.contains("gpt-5.5") {
                return Rate(inputPerMillion: 5, outputPerMillion: 30, cacheReadPerMillion: 0.50, cacheWritePerMillion: 6.25)
            }
            if normalized.contains("gpt-5.4-mini") {
                return Rate(inputPerMillion: 0.75, outputPerMillion: 4.50, cacheReadPerMillion: 0.075, cacheWritePerMillion: 0.9375)
            }
            if normalized.contains("gpt-5.4-nano") {
                return Rate(inputPerMillion: 0.20, outputPerMillion: 1.25, cacheReadPerMillion: 0.02, cacheWritePerMillion: 0.25)
            }
            if normalized.contains("gpt-5.4") {
                return Rate(inputPerMillion: 2.50, outputPerMillion: 15, cacheReadPerMillion: 0.25, cacheWritePerMillion: 3.125)
            }
            if normalized.contains("gpt-5.3-codex") {
                return Rate(inputPerMillion: 1.75, outputPerMillion: 14, cacheReadPerMillion: 0.175, cacheWritePerMillion: 2.1875)
            }
            if normalized.contains("gpt-5.6-sol") || normalized == "gpt-5.6" {
                return Rate(inputPerMillion: 5, outputPerMillion: 30, cacheReadPerMillion: 0.50, cacheWritePerMillion: 6.25)
            }
            if normalized.contains("gpt-5.6-terra") {
                return Rate(inputPerMillion: 2.50, outputPerMillion: 15, cacheReadPerMillion: 0.25, cacheWritePerMillion: 3.125)
            }
            if normalized.contains("gpt-5.6-luna") {
                return Rate(inputPerMillion: 1, outputPerMillion: 6, cacheReadPerMillion: 0.10, cacheWritePerMillion: 1.25)
            }
            if normalized.contains("mini") {
                return Rate(inputPerMillion: 0.15, outputPerMillion: 0.60, cacheReadPerMillion: 0.075, cacheWritePerMillion: 0.15)
            }
            return Rate(inputPerMillion: 0, outputPerMillion: 0, cacheReadPerMillion: 0, cacheWritePerMillion: 0)
        case .gemini:
            if normalized.contains("gemini-3.5-flash") {
                return Rate(inputPerMillion: 1.50, outputPerMillion: 9, cacheReadPerMillion: 0.15, cacheWritePerMillion: 1.50)
            }
            if normalized.contains("gemini-3.1-pro") {
                return Rate(inputPerMillion: 2, outputPerMillion: 12, cacheReadPerMillion: 0.20, cacheWritePerMillion: 2)
            }
            return Rate(inputPerMillion: 0, outputPerMillion: 0, cacheReadPerMillion: 0, cacheWritePerMillion: 0)
        case .unknown:
            return Rate(inputPerMillion: 0, outputPerMillion: 0, cacheReadPerMillion: 0, cacheWritePerMillion: 0)
        }
    }
}
