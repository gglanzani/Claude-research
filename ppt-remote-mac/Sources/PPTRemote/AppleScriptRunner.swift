import Foundation

final class AppleScriptRunner {
    func run(named name: String) -> (ok: Bool, message: String) {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: "applescript",
            subdirectory: "Scripts"
        ), let source = try? String(contentsOf: url, encoding: .utf8) else {
            return (false, "script not found: \(name)")
        }

        var error: NSDictionary?
        let script = NSAppleScript(source: source)
        script?.executeAndReturnError(&error)
        if let error {
            let msg = (error[NSAppleScript.errorMessage] as? String) ?? "\(error)"
            return (false, msg)
        }
        return (true, "")
    }
}
