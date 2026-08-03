import Foundation

final class OpenAIProxyService {
    typealias EventHandler = @Sendable ([UsageEvent]) async -> Void

    private var server: LocalHTTPServer?
    private let normalizer = OTLPNormalizer()

    func start(
        port: UInt16,
        baseURL: URL,
        storageOptions: UsageMetadataStorageOptions,
        eventHandler: @escaping EventHandler
    ) throws {
        stop()
        let server = LocalHTTPServer(name: "OpenAIProxy", port: port) { [normalizer] request in
            if request.method == "GET", request.path == "/health" {
                return .json(["status": "ok", "service": "openai-proxy"])
            }
            guard let targetURL = URL(string: request.path, relativeTo: baseURL)?.absoluteURL else {
                return .json(statusCode: 400, ["error": "Invalid proxy target path."])
            }

            do {
                var outbound = URLRequest(url: targetURL)
                outbound.httpMethod = request.method
                outbound.httpBody = request.body
                for (key, value) in request.headers {
                    let lowercased = key.lowercased()
                    guard lowercased != "host",
                          lowercased != "content-length",
                          lowercased != "connection"
                    else { continue }
                    outbound.setValue(value, forHTTPHeaderField: key)
                }

                let (data, response) = try await URLSession.shared.data(for: outbound)
                let events = (try? normalizer.events(
                    from: data,
                    defaultSource: "OpenAI Proxy",
                    storageOptions: storageOptions
                )) ?? []
                if !events.isEmpty {
                    await eventHandler(events)
                }

                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 200
                let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "application/json"
                return HTTPResponse(
                    statusCode: statusCode,
                    headers: ["Content-Type": contentType],
                    body: data
                )
            } catch {
                AppLog.proxy.error("Proxy forwarding failed: \(error.localizedDescription)")
                return .json(statusCode: 502, ["error": error.localizedDescription])
            }
        }
        try server.start()
        self.server = server
    }

    func stop() {
        server?.stop()
        server = nil
    }
}
