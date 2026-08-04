import Foundation

/// Localhost receiver for CLI hook events. Hook commands (installed by the
/// adapters) POST the CLI's stdin JSON here; we decode, hand the normalized
/// event to the session store, and reply fast so hooks never slow the CLI.
final class HookServer: @unchecked Sendable {
    /// Consumes a decoded event and optionally returns the raw JSON string
    /// to emit as hook stdout (permission decisions, terminalSequence…).
    /// `nil` → `{"ok": true}`. May suspend (parked approvals).
    typealias EventSink = @Sendable (SessionEvent) async -> String?

    private let port: UInt16
    private var server: LocalHTTPServer?
    private let eventSink: EventSink

    private(set) var isRunning = false

    init(port: UInt16 = AppConstants.defaultHookPort, eventSink: @escaping EventSink) {
        self.port = port
        self.eventSink = eventSink
    }

    func start() throws {
        guard server == nil else { return }
        let sink = eventSink
        let server = LocalHTTPServer(name: "Hooks", port: port) { request in
            await Self.handle(request: request, sink: sink)
        }
        try server.start()
        self.server = server
        isRunning = true
        AppLog.telemetry.info("Hook server listening on 127.0.0.1:\(self.port)")
    }

    func stop() {
        server?.stop()
        server = nil
        isRunning = false
    }

    private static func handle(request: HTTPRequest, sink: EventSink) async -> HTTPResponse {
        switch (request.method, request.path) {
        case ("GET", "/health"):
            return .json(["status": "ok", "app": AppConstants.appName])

        // The route's last segment says which CLI posted, which decides both
        // the agent the session belongs to and the payload dialect.
        case ("POST", let path) where path.hasPrefix("/hook/"):
            let source = String(path.dropFirst("/hook/".count))
            guard let agent = HookFamilyCLI.agentKind(forSource: source),
                  let dialect = HookFamilyCLI.dialect(forSource: source)
            else {
                return .json(statusCode: 404, ["error": "unknown route"])
            }
            do {
                let event: SessionEvent
                switch dialect {
                case .claude:
                    event = try HookRouter.decodeClaudeEvent(
                        body: request.body,
                        headers: request.headers,
                        agent: agent
                    )
                case .cursor:
                    event = try CursorHookRouter.decode(
                        body: request.body,
                        headers: request.headers
                    )
                case .gemini:
                    event = try GeminiHookRouter.decode(
                        body: request.body,
                        headers: request.headers
                    )
                }
                if let payload = await sink(event) {
                    return HTTPResponse(
                        statusCode: 200,
                        headers: ["Content-Type": "application/json"],
                        body: Data(payload.utf8)
                    )
                }
                return .json(["ok": true])
            } catch {
                AppLog.telemetry.error("Hook decode failed: \(error)")
                // Always 200 with no directive output: hooks must stay fail-open.
                return .json(["ok": false])
            }

        default:
            return .json(statusCode: 404, ["error": "unknown route"])
        }
    }
}
