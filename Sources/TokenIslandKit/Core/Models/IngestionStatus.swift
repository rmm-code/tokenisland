import Foundation

enum ServiceHealth: String, Codable, Hashable, Sendable {
    case stopped
    case starting
    case running
    case degraded
    case failed
}

struct IngestionStatus: Hashable, Sendable {
    var otlpHealth: ServiceHealth
    var proxyHealth: ServiceHealth
    var lastEventAt: Date?
    var lastErrorMessage: String?
    var ingestedEventCount: Int

    static let idle = IngestionStatus(
        otlpHealth: .stopped,
        proxyHealth: .stopped,
        lastEventAt: nil,
        lastErrorMessage: nil,
        ingestedEventCount: 0
    )
}
