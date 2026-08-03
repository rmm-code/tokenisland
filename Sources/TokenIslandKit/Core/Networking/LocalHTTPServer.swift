import Foundation
import Network

struct HTTPRequest: Sendable {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data
}

struct HTTPResponse: Sendable {
    var statusCode: Int
    var headers: [String: String]
    var body: Data

    static func json(statusCode: Int = 200, _ object: [String: Any]) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [])) ?? Data()
        return HTTPResponse(
            statusCode: statusCode,
            headers: ["Content-Type": "application/json"],
            body: data
        )
    }

    static func text(statusCode: Int = 200, _ text: String) -> HTTPResponse {
        HTTPResponse(
            statusCode: statusCode,
            headers: ["Content-Type": "text/plain; charset=utf-8"],
            body: Data(text.utf8)
        )
    }

    var serialized: Data {
        var lines = [
            "HTTP/1.1 \(statusCode) \(Self.reasonPhrase(for: statusCode))",
            "Content-Length: \(body.count)",
            "Connection: close"
        ]
        for (key, value) in headers {
            lines.append("\(key): \(value)")
        }
        lines.append("")
        lines.append("")
        var data = Data(lines.joined(separator: "\r\n").utf8)
        data.append(body)
        return data
    }

    private static func reasonPhrase(for statusCode: Int) -> String {
        switch statusCode {
        case 200: "OK"
        case 202: "Accepted"
        case 400: "Bad Request"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 500: "Internal Server Error"
        case 502: "Bad Gateway"
        default: "OK"
        }
    }
}

enum LocalHTTPServerError: Error, LocalizedError {
    case invalidPort(UInt16)
    case malformedRequest

    var errorDescription: String? {
        switch self {
        case .invalidPort(let port):
            "Invalid local server port: \(port)"
        case .malformedRequest:
            "Malformed HTTP request."
        }
    }
}

final class LocalHTTPServer: @unchecked Sendable {
    typealias Handler = @Sendable (HTTPRequest) async -> HTTPResponse

    private let name: String
    private let port: UInt16
    private let handler: Handler
    private let queue: DispatchQueue
    private var listener: NWListener?

    init(name: String, port: UInt16, handler: @escaping Handler) {
        self.name = name
        self.port = port
        self.handler = handler
        self.queue = DispatchQueue(label: "TokenIsland.\(name).HTTPServer")
    }

    /// Loopback ONLY. Plain `NWParameters.tcp` binds every interface, which put
    /// the hook receiver on the LAN: anyone on the same Wi-Fi could POST session
    /// events and forge approval prompts in the user's notch. The log line
    /// always claimed 127.0.0.1 — the socket said `*`.
    static func loopbackParameters() -> NWParameters {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredInterfaceType = .loopback
        return parameters
    }

    func start() throws {
        guard listener == nil else { return }
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw LocalHTTPServerError.invalidPort(port)
        }
        let listener = try NWListener(using: Self.loopbackParameters(), on: endpointPort)
        listener.stateUpdateHandler = { state in
            AppLog.telemetry.info("\(self.name) server state: \(String(describing: state))")
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveChunk(connection, buffer: Data())
    }

    /// Requests can arrive split across TCP segments (URLSession sends
    /// headers and body separately; large hook payloads fragment too), so
    /// accumulate until Content-Length is satisfied.
    private func receiveChunk(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_000_000) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                AppLog.telemetry.error("\(self.name) receive failed: \(error.localizedDescription)")
                connection.cancel()
                return
            }
            var buffer = buffer
            if let data {
                buffer.append(data)
            }
            guard buffer.count <= 4_000_000 else {
                connection.send(
                    content: HTTPResponse.json(statusCode: 400, ["error": "payload too large"]).serialized,
                    completion: .contentProcessed { _ in connection.cancel() }
                )
                return
            }
            if Self.isRequestComplete(buffer) || isComplete {
                guard !buffer.isEmpty else {
                    connection.cancel()
                    return
                }
                self.respond(connection, requestData: buffer)
            } else {
                self.receiveChunk(connection, buffer: buffer)
            }
        }
    }

    private func respond(_ connection: NWConnection, requestData: Data) {
        Task {
            let response: HTTPResponse
            do {
                let request = try Self.parseRequest(requestData)
                response = await self.handler(request)
            } catch {
                response = .json(statusCode: 400, ["error": error.localizedDescription])
            }
            connection.send(content: response.serialized, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    /// True once the header block is present and the body has at least
    /// Content-Length bytes.
    static func isRequestComplete(_ data: Data) -> Bool {
        guard let headerRange = data.range(of: Data("\r\n\r\n".utf8)) else { return false }
        guard let headerString = String(data: data[..<headerRange.lowerBound], encoding: .utf8) else {
            return false
        }
        var contentLength = 0
        for line in headerString.components(separatedBy: "\r\n").dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            guard key.caseInsensitiveCompare("Content-Length") == .orderedSame else { continue }
            contentLength = Int(String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)) ?? 0
            break
        }
        let bodyCount = data.endIndex - headerRange.upperBound
        return bodyCount >= contentLength
    }

    private static func parseRequest(_ data: Data) throws -> HTTPRequest {
        let delimiter = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: delimiter),
              let headerString = String(data: data[..<headerRange.lowerBound], encoding: .utf8)
        else {
            throw LocalHTTPServerError.malformedRequest
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            throw LocalHTTPServerError.malformedRequest
        }
        let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else {
            throw LocalHTTPServerError.malformedRequest
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }

        let bodyStart = headerRange.upperBound
        let body = bodyStart < data.endIndex ? Data(data[bodyStart...]) : Data()
        return HTTPRequest(method: parts[0], path: parts[1], headers: headers, body: body)
    }
}
