import Foundation
import Network

public final class AgentStatusHTTPServer: @unchecked Sendable {
    public let port: UInt16
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.agentlight.http-server")
    private let store: AgentStateStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var isRunning = false

    public init(port: UInt16 = 43999, store: AgentStateStore = AgentStateStore()) throws {
        self.port = port
        self.store = store
        encoder.keyEncodingStrategy = .convertToSnakeCase
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw ServerError.invalidPort }
        self.listener = try NWListener(using: .tcp, on: nwPort)
        listener.parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host("127.0.0.1"), port: nwPort)
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                fputs("AgentLight daemon failed: \(error)\n", stderr)
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: self.queue)
            HTTPConnection(connection: connection, store: self.store, encoder: self.encoder, decoder: self.decoder).start()
        }
        listener.start(queue: queue)
    }

    public func stop() {
        listener.cancel()
        isRunning = false
    }

    public enum ServerError: Error {
        case invalidPort
    }
}

private final class HTTPConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let store: AgentStateStore
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var buffer = Data()
    private var didRespond = false

    init(connection: NWConnection, store: AgentStateStore, encoder: JSONEncoder, decoder: JSONDecoder) {
        self.connection = connection
        self.store = store
        self.encoder = encoder
        self.decoder = decoder
    }

    func start() {
        receive()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self, !self.didRespond else { return }
            if let data { self.buffer.append(data) }
            if let request = self.parseRequest() {
                self.respond(to: request)
            } else if isComplete || error != nil {
                self.respond(status: 400, body: ["error": "invalid HTTP request"])
            } else {
                self.receive()
            }
        }
    }

    private func parseRequest() -> HTTPRequest? {
        guard let separator = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = buffer[..<separator.lowerBound]
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let requestParts = requestLine.split(separator: " ")
        guard requestParts.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 { headers[parts[0].lowercased()] = parts[1].trimmingCharacters(in: .whitespaces) }
        }
        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = separator.upperBound
        guard buffer.count >= bodyStart + contentLength else { return nil }
        let body = Data(buffer[bodyStart..<(bodyStart + contentLength)])
        return HTTPRequest(method: String(requestParts[0]), path: String(requestParts[1]), body: body)
    }

    private func respond(to request: HTTPRequest) {
        switch (request.method, request.path) {
        case ("GET", "/v1/health"):
            respond(status: 200, body: ["ok": true])
        case ("GET", "/v1/sessions"):
            respond(status: 200, body: store.snapshot())
        case ("POST", "/v1/events"):
            do {
                let event = try decoder.decode(AgentEvent.self, from: request.body)
                if event.event?.lowercased() == "session_end" {
                    store.remove(sessionID: event.sessionID)
                } else {
                    _ = store.apply(event)
                }
                respond(status: 202, body: ["accepted": true])
            } catch {
                respond(status: 400, body: ["error": "invalid event payload"])
            }
        case ("DELETE", _) where request.path.hasPrefix("/v1/sessions/"):
            let sessionID = String(request.path.dropFirst("/v1/sessions/".count))
            store.remove(sessionID: sessionID.removingPercentEncoding ?? sessionID)
            respond(status: 204, body: EmptyResponse())
        default:
            respond(status: 404, body: ["error": "not found"])
        }
    }

    private func respond<T: Encodable>(status: Int, body: T) {
        didRespond = true
        let bodyData = (try? encoder.encode(body)) ?? Data("{}".utf8)
        let reason = status == 202 ? "Accepted" : status == 204 ? "No Content" : status == 400 ? "Bad Request" : status == 404 ? "Not Found" : "OK"
        let response = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        var data = Data(response.utf8)
        data.append(bodyData)
        connection.send(content: data, completion: .contentProcessed { [weak self] _ in self?.connection.cancel() })
    }

    private struct HTTPRequest {
        let method: String
        let path: String
        let body: Data
    }

    private struct EmptyResponse: Encodable {}
}
