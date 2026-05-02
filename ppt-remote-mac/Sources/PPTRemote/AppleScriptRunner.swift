import Foundation

final class AppleScriptRunner {
    func run(named name: String) -> (ok: Bool, message: String) {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: "applescript",
            subdirectory: "Scripts"
        ) else {
            return (false, "script not found: \(name)")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [url.path]
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
            let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let ok = process.terminationStatus == 0
            let msg = (ok ? out : err).trimmingCharacters(in: .whitespacesAndNewlines)
            return (ok, msg)
        } catch {
            return (false, "\(error)")
        }
    }
}
