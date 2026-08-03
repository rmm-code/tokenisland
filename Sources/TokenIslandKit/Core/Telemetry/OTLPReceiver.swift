import Foundation

final class OTLPReceiver {
    typealias EventHandler = @Sendable ([UsageEvent]) async -> Void

    private var server: LocalHTTPServer?
    private let normalizer = OTLPNormalizer()

    func start(port: UInt16, storageOptions: UsageMetadataStorageOptions, eventHandler: @escaping EventHandler) throws {
        stop()
        let server = LocalHTTPServer(name: "OTLPReceiver", port: port) { [normalizer] request in
            if request.method == "GET", request.path == "/health" {
                return .json(["status": "ok", "service": "otlp"])
            }
            guard request.method == "POST" else {
                return .json(statusCode: 405, ["error": "Only POST is supported for telemetry ingestion."])
            }
            do {
                let source = Self.defaultSource(for: request.path)
                let events = try normalizer.events(
                    from: request.body,
                    defaultSource: source,
                    storageOptions: storageOptions
                )
                await eventHandler(events)
                return .json(statusCode: 202, ["ingested": events.count])
            } catch {
                AppLog.telemetry.error("OTLP normalization failed: \(error.localizedDescription)")
                return .json(statusCode: 400, ["error": error.localizedDescription])
            }
        }
        try server.start()
        self.server = server
    }

    func stop() {
        server?.stop()
        server = nil
    }

    private static func defaultSource(for path: String) -> String {
        if path.lowercased().contains("claude") {
            return "Generic Claude Source"
        }
        if path.lowercased().contains("openai") || path.lowercased().contains("codex") {
            return "Generic OpenAI Source"
        }
        return "Local OTLP"
    }
}
