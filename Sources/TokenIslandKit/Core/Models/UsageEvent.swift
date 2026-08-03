import Foundation

struct UsageEvent: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var timestamp: Date
    var provider: AIProvider
    var sourceApp: String
    var projectName: String?
    var projectPath: String?
    var model: String
    var inputTokens: Int
    var outputTokens: Int
    var cacheReadTokens: Int
    var cacheWriteTokens: Int
    var estimatedCostUSD: Decimal
    var requestID: String?
    var latencyMS: Int?
    var sessionID: String?
    var rawMetadataJSON: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        provider: AIProvider,
        sourceApp: String,
        projectName: String? = nil,
        projectPath: String? = nil,
        model: String,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheReadTokens: Int = 0,
        cacheWriteTokens: Int = 0,
        estimatedCostUSD: Decimal = 0,
        requestID: String? = nil,
        latencyMS: Int? = nil,
        sessionID: String? = nil,
        rawMetadataJSON: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.provider = provider
        self.sourceApp = sourceApp
        self.projectName = projectName
        self.projectPath = projectPath
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.estimatedCostUSD = estimatedCostUSD
        self.requestID = requestID
        self.latencyMS = latencyMS
        self.sessionID = sessionID
        self.rawMetadataJSON = rawMetadataJSON
    }

    var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens
    }
}
