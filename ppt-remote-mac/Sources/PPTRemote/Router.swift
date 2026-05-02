import Foundation

final class Router {
    private let scripts: AppleScriptRunner
    private let mover: CursorMover

    private static let actionScripts: [String: String] = [
        "next": "next",
        "prev": "prev",
        "start": "start",
        "end": "end",
        "laser": "laser",
    ]

    init(scripts: AppleScriptRunner, mover: CursorMover) {
        self.scripts = scripts
        self.mover = mover
    }

    func handle(_ req: HTTPRequest) -> HTTPResponse {
        switch (req.method, req.path) {
        case ("GET", "/"), ("GET", "/index.html"):
            return serveIndex()
        case ("POST", let p) where p.hasPrefix("/api/"):
            return handleAction(String(p.dropFirst("/api/".count)), body: req.body)
        default:
            return .notFound()
        }
    }

    private func serveIndex() -> HTTPResponse {
        guard let url = Bundle.module.url(forResource: "index", withExtension: "html"),
              let data = try? Data(contentsOf: url) else {
            return .notFound()
        }
        return HTTPResponse.ok(data, contentType: "text/html; charset=utf-8")
    }

    private func handleAction(_ action: String, body: Data) -> HTTPResponse {
        if let script = Router.actionScripts[action] {
            let result = scripts.run(named: script)
            return HTTPResponse.json(["ok": result.ok, "message": result.message])
        }
        if action == "move" {
            let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
            let dx = (json["dx"] as? NSNumber)?.doubleValue ?? 0
            let dy = (json["dy"] as? NSNumber)?.doubleValue ?? 0
            let p = mover.move(dx: dx, dy: dy)
            return HTTPResponse.json(["ok": true, "x": p.x, "y": p.y])
        }
        return .notFound()
    }
}
