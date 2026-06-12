import Foundation
import Network

public struct BrowserBridgeInfo: Equatable, Sendable {
    public var port: UInt16
    public var secret: String
    public var configURL: URL

    public var usageURL: String {
        "http://127.0.0.1:\(port)/usage"
    }
}

public final class BrowserBridge {
    private let secret: String
    private let onUsage: (UsageEvent) -> Void
    private let onReady: (BrowserBridgeInfo) -> Void
    private let onError: (String) -> Void
    private let queue = DispatchQueue(label: "app.sootling.browser-bridge", qos: .utility)
    private var listener: NWListener?
    private var configURL: URL?

    public init(
        secret: String = BrowserBridge.makeSecret(),
        onUsage: @escaping (UsageEvent) -> Void,
        onReady: @escaping (BrowserBridgeInfo) -> Void,
        onError: @escaping (String) -> Void
    ) {
        self.secret = secret
        self.onUsage = onUsage
        self.onReady = onReady
        self.onError = onError
    }

    public func start(configDirectory: URL) throws {
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        configURL = configDirectory.appendingPathComponent("browser-bridge.json")

        let listener = try NWListener(using: .tcp, on: .any)
        listener.stateUpdateHandler = { [weak self] state in
            self?.handle(state: state)
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(state: NWListener.State) {
        switch state {
        case .ready:
            guard let port = listener?.port,
                  let configURL else {
                return
            }
            let info = BrowserBridgeInfo(port: port.rawValue, secret: secret, configURL: configURL)
            writeConfig(info)
            onReady(info)
        case .failed(let error):
            onError("Browser bridge failed: \(error.localizedDescription)")
        default:
            break
        }
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            if let error {
                self.onError("Browser bridge receive failed: \(error.localizedDescription)")
                connection.cancel()
                return
            }

            var nextBuffer = buffer
            if let data {
                nextBuffer.append(data)
            }

            if let request = HTTPRequest(data: nextBuffer) {
                self.respond(to: request, on: connection)
                return
            }

            if isComplete || nextBuffer.count > 128 * 1024 {
                self.send(status: 400, body: "Bad Request", on: connection)
                return
            }

            self.receive(on: connection, buffer: nextBuffer)
        }
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection) {
        if request.method == "OPTIONS" {
            send(status: 204, body: "", on: connection)
            return
        }

        guard request.method == "POST", request.path == "/usage" else {
            send(status: 404, body: "Not Found", on: connection)
            return
        }

        guard request.headers["authorization"] == "Bearer \(secret)" else {
            send(status: 401, body: "Unauthorized", on: connection)
            return
        }

        do {
            let payload = try JSONDecoder().decode(BrowserUsagePayload.self, from: request.body)
            guard let event = payload.event else {
                send(status: 422, body: "Invalid usage event", on: connection)
                return
            }
            onUsage(event)
            send(status: 202, body: "Accepted", on: connection)
        } catch {
            send(status: 400, body: "Invalid JSON", on: connection)
        }
    }

    private func send(status: Int, body: String, on connection: NWConnection) {
        let reason: String
        switch status {
        case 202: reason = "Accepted"
        case 204: reason = "No Content"
        case 400: reason = "Bad Request"
        case 401: reason = "Unauthorized"
        case 404: reason = "Not Found"
        case 422: reason = "Unprocessable Content"
        default: reason = "OK"
        }

        let bodyData = Data(body.utf8)
        let response = """
        HTTP/1.1 \(status) \(reason)\r
        Content-Length: \(bodyData.count)\r
        Content-Type: text/plain; charset=utf-8\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Headers: Authorization, Content-Type\r
        Access-Control-Allow-Methods: POST, OPTIONS\r
        Connection: close\r
        \r
        """
        var data = Data(response.utf8)
        data.append(bodyData)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func writeConfig(_ info: BrowserBridgeInfo) {
        let payload: [String: Any] = [
            "port": info.port,
            "secret": info.secret,
            "usageURL": info.usageURL,
            "privacy": "Browser text stays in the extension; Sootling receives token counts and metadata only."
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        try? data.write(to: info.configURL, options: [.atomic])
    }

    public static func makeSecret() -> String {
        "\(UUID().uuidString)-\(UUID().uuidString)"
    }
}

private struct BrowserUsagePayload: Decodable {
    var timestamp: String?
    var source: String
    var model: String?
    var tokensIn: Int
    var tokensOut: Int?
    var cachedInputTokens: Int?

    var event: UsageEvent? {
        guard let source = UsageSource(rawValue: source) else {
            return nil
        }
        let date = timestamp.flatMap {
            DateParsers.iso8601.date(from: $0) ?? DateParsers.iso8601NoFraction.date(from: $0)
        } ?? Date()

        return UsageEvent(
            timestamp: date,
            source: source,
            model: model ?? "browser-estimate",
            tokensIn: tokensIn,
            tokensOut: tokensOut ?? 0,
            cachedInputTokens: cachedInputTokens ?? 0
        )
    }
}

private struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data

    init?(data: Data) {
        guard let separator = data.range(of: Data("\r\n\r\n".utf8)) else {
            return nil
        }

        let headerData = data[..<separator.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return nil
        }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return nil
        }
        let requestParts = requestLine.split(separator: " ")
        guard requestParts.count >= 2 else {
            return nil
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else {
                continue
            }
            let key = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[String(key)] = value
        }

        let bodyStart = separator.upperBound
        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        guard data.count >= bodyStart + contentLength else {
            return nil
        }

        self.method = String(requestParts[0])
        self.path = String(requestParts[1])
        self.headers = headers
        self.body = Data(data[bodyStart..<(bodyStart + contentLength)])
    }
}
