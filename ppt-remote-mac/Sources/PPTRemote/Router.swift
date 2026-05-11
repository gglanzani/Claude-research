import Foundation
import ApplicationServices

final class Router {
    private let scripts: AppleScriptRunner
    private let mover: CursorMover
    private let token: String

    private static let actionScripts: [String: String] = [
        "next": "next",
        "prev": "prev",
        "start": "start",
        "end": "end",
        "laser": "laser",
    ]

    init(scripts: AppleScriptRunner, mover: CursorMover, token: String) {
        self.scripts = scripts
        self.mover = mover
        self.token = token
    }

    func handle(_ req: HTTPRequest) -> HTTPResponse {
        let base = "/\(token)"
        let apiBase = "\(base)/api/"

        switch (req.method, req.path) {
        case ("GET", base), ("GET", base + "/"), ("GET", base + "/index.html"):
            return serveIndex()
        case ("POST", let p) where p.hasPrefix(apiBase):
            return handleAction(String(p.dropFirst(apiBase.count)), body: req.body)
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
            if action == "laser" && !AXIsProcessTrusted() {
                return HTTPResponse.json(["ok": false, "message": "Accessibility not granted — open System Settings → Privacy & Security → Accessibility and enable PPTRemote"])
            }
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
