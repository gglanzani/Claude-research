import AppKit
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let port: UInt16 = 8080
    private var statusItem: NSStatusItem!
    private var server: HTTPServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        startServer()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.on.rectangle",
                accessibilityDescription: "PPT Remote"
            )
            button.toolTip = "PPT Remote"
        }

        let menu = NSMenu()
        let urlItem = NSMenuItem(title: "Starting…", action: #selector(copyURL), keyEquivalent: "")
        urlItem.target = self
        urlItem.tag = 100
        menu.addItem(urlItem)
        menu.addItem(NSMenuItem.separator())
        let copyItem = NSMenuItem(title: "Copy URL", action: #selector(copyURL), keyEquivalent: "c")
        copyItem.target = self
        menu.addItem(copyItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        statusItem.menu = menu
    }

    private func startServer() {
        let scripts = AppleScriptRunner()
        let mover = CursorMover()
        let router = Router(scripts: scripts, mover: mover)
        do {
            let server = try HTTPServer(port: port, handler: router.handle)
            try server.start()
            self.server = server
            updateMenuURL()
        } catch {
            let alert = NSAlert()
            alert.messageText = "PPT Remote could not start"
            alert.informativeText = "\(error)"
            alert.alertStyle = .critical
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    private func currentURL() -> String {
        let host = localIP() ?? "localhost"
        return "http://\(host):\(port)"
    }

    private func updateMenuURL() {
        if let item = statusItem.menu?.item(withTag: 100) {
            item.title = currentURL()
        }
    }

    @objc private func copyURL() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(currentURL(), forType: .string)
    }
}

func localIP() -> String? {
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
    defer { freeifaddrs(ifaddr) }

    var fallback: String?
    var ptr: UnsafeMutablePointer<ifaddrs>? = first
    while let p = ptr {
        let i = p.pointee
        let name = String(cString: i.ifa_name)
        let isLoopback = (i.ifa_flags & UInt32(IFF_LOOPBACK)) != 0
        if !isLoopback, let sa = i.ifa_addr, sa.pointee.sa_family == sa_family_t(AF_INET) {
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(sa, socklen_t(sa.pointee.sa_len),
                        &host, socklen_t(host.count),
                        nil, 0, NI_NUMERICHOST)
            let address = String(cString: host)
            if !address.hasPrefix("169.254") {
                if name == "en0" || name == "en1" { return address }
                fallback = fallback ?? address
            }
        }
        ptr = i.ifa_next
    }
    return fallback
}
