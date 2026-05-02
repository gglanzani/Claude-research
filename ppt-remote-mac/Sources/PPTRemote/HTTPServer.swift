import Foundation
import Network

struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
}

struct HTTPResponse {
    let status: Int
    let headers: [String: String]
    let body: Data

    static func ok(_ body: Data, contentType: String) -> HTTPResponse {
        HTTPResponse(status: 200, headers: ["Content-Type": contentType], body: body)
    }

    static func json(_ obj: [String: Any]) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
    }

    static func notFound() -> HTTPResponse {
        HTTPResponse(status: 404, headers: ["Content-Type": "text/plain"], body: Data("not found".utf8))
    }

    func serialize() -> Data {
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        var h = headers
        h["Content-Length"] = "\(body.count)"
        h["Connection"] = "close"
        for (k, v) in h { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        var data = Data(head.utf8)
        data.append(body)
        return data
    }

    private var reason: String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        default: return "Status"
        }
    }
}

final class HTTPServer {
    private let port: NWEndpoint.Port
    private var listener: NWListener?
    private let handler: (HTTPRequest) -> HTTPResponse
    private let queue = DispatchQueue(label: "PPTRemote.server", qos: .userInitiated)

    init(port: UInt16, handler: @escaping (HTTPRequest) -> HTTPResponse) throws {
        guard let p = NWEndpoint.Port(rawValue: port) else {
            throw NSError(domain: "HTTPServer", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "invalid port \(port)"])
        }
        self.port = p
        self.handler = handler
    }

    func start() throws {
        let listener = try NWListener(using: .tcp, on: port)
        listener.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, _ in
            guard let self else { conn.cancel(); return }
            var buf = buffer
            if let data { buf.append(data) }

            if let req = parseRequest(buf) {
                let resp = self.handler(req)
                conn.send(content: resp.serialize(), completion: .contentProcessed { _ in
                    conn.cancel()
                })
                return
            }

            if isComplete || buf.count > 1_048_576 {
                conn.cancel()
                return
            }
            self.receive(conn, buffer: buf)
        }
    }
}

private func parseRequest(_ data: Data) -> HTTPRequest? {
    let separator = Data("\r\n\r\n".utf8)
    guard let range = data.range(of: separator) else { return nil }

    let headerBytes = data.subdata(in: 0..<range.lowerBound)
    guard let headerStr = String(data: headerBytes, encoding: .utf8) else { return nil }

    let lines = headerStr.components(separatedBy: "\r\n")
    guard let firstLine = lines.first else { return nil }
    let parts = firstLine.split(separator: " ").map(String.init)
    guard parts.count >= 2 else { return nil }

    var headers: [String: String] = [:]
    for line in lines.dropFirst() where !line.isEmpty {
        guard let colon = line.firstIndex(of: ":") else { continue }
        let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
        let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        headers[key] = value
    }

    let bodyStart = range.upperBound
    let expected = Int(headers["content-length"] ?? "0") ?? 0
    let available = data.count - bodyStart
    if available < expected { return nil }
    let body = expected > 0 ? data.subdata(in: bodyStart..<(bodyStart + expected)) : Data()

    return HTTPRequest(method: parts[0], path: parts[1], headers: headers, body: body)
}
