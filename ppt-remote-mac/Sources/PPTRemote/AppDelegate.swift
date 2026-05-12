import AppKit
import CoreImage
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let port: UInt16 = 8080
    private let token: String = {
        let chars = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<8).map { _ in chars[Int.random(in: 0..<chars.count)] })
    }()
    private var statusItem: NSStatusItem!
    private var server: HTTPServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupAppIcon()
        requestAccessibilityIfNeeded()
        setupMenuBar()
        startServer()
    }

    private func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let alert = NSAlert()
            alert.messageText = "Accessibility permission required"
            alert.informativeText = "PPT Remote needs Accessibility access to send the laser-pointer keystroke.\n\nGrant access in System Settings → Privacy & Security → Accessibility, then relaunch the app."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
    }

    private func setupAppIcon() {
        let s: CGFloat = 512
        let icon = NSImage(size: NSSize(width: s, height: s), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let rgb = CGColorSpaceCreateDeviceRGB()

            // Clip to macOS squircle
            let squircle = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                                  cornerWidth: s * 0.2237, cornerHeight: s * 0.2237, transform: nil)
            ctx.addPath(squircle); ctx.clip()

            // Background gradient: vivid royal blue → teal
            let bg = CGGradient(colorsSpace: rgb, colors: [
                CGColor(red: 0.08, green: 0.15, blue: 0.72, alpha: 1),
                CGColor(red: 0.00, green: 0.52, blue: 0.62, alpha: 1),
            ] as CFArray, locations: nil)!
            ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: s),
                                   end: CGPoint(x: s, y: 0), options: [])

            // Subtle top sheen
            let sheen = CGGradient(colorsSpace: rgb, colors: [
                CGColor(red: 1, green: 1, blue: 1, alpha: 0.16),
                CGColor(red: 1, green: 1, blue: 1, alpha: 0.00),
            ] as CFArray, locations: nil)!
            ctx.drawLinearGradient(sheen, start: CGPoint(x: s / 2, y: s),
                                   end: CGPoint(x: s / 2, y: s * 0.50), options: [])

            // 16:9 slide shape, centred and slightly raised
            let sw = s * 0.62, sh = sw * 9 / 16
            let sx = (s - sw) / 2, sy = (s - sh) / 2 + s * 0.015
            let slideRect = CGRect(x: sx, y: sy, width: sw, height: sh)
            let slideR = s * 0.025
            let slidePath = CGPath(roundedRect: slideRect, cornerWidth: slideR,
                                   cornerHeight: slideR, transform: nil)

            ctx.addPath(slidePath)
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.20))
            ctx.fillPath()

            ctx.addPath(slidePath)
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.60))
            ctx.setLineWidth(s * 0.008)
            ctx.strokePath()

            // Content lines inside slide (left side, y increases upward)
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.38))
            ctx.setLineWidth(s * 0.018)
            ctx.setLineCap(.round)
            let lx = sx + sw * 0.10
            let titleY = sy + sh * 0.72, body1Y = sy + sh * 0.52, body2Y = sy + sh * 0.34
            ctx.move(to: CGPoint(x: lx, y: titleY)); ctx.addLine(to: CGPoint(x: lx + sw * 0.50, y: titleY)); ctx.strokePath()
            ctx.move(to: CGPoint(x: lx, y: body1Y)); ctx.addLine(to: CGPoint(x: lx + sw * 0.40, y: body1Y)); ctx.strokePath()
            ctx.move(to: CGPoint(x: lx, y: body2Y)); ctx.addLine(to: CGPoint(x: lx + sw * 0.32, y: body2Y)); ctx.strokePath()

            // Red laser dot — right side of the slide
            let dotX = sx + sw * 0.76, dotY = sy + sh * 0.52
            let dotR = s * 0.062

            // Outer glow
            let outerGlow = CGGradient(colorsSpace: rgb, colors: [
                CGColor(red: 1.0, green: 0.15, blue: 0.20, alpha: 0.40),
                CGColor(red: 1.0, green: 0.15, blue: 0.20, alpha: 0.00),
            ] as CFArray, locations: nil)!
            ctx.drawRadialGradient(outerGlow, startCenter: CGPoint(x: dotX, y: dotY), startRadius: 0,
                                   endCenter: CGPoint(x: dotX, y: dotY), endRadius: dotR * 4.0, options: [])

            // Inner glow
            let glow = CGGradient(colorsSpace: rgb, colors: [
                CGColor(red: 1.0, green: 0.15, blue: 0.20, alpha: 0.85),
                CGColor(red: 1.0, green: 0.10, blue: 0.15, alpha: 0.00),
            ] as CFArray, locations: nil)!
            ctx.drawRadialGradient(glow, startCenter: CGPoint(x: dotX, y: dotY), startRadius: 0,
                                   endCenter: CGPoint(x: dotX, y: dotY), endRadius: dotR * 2.2, options: [])

            // Dot core
            ctx.addEllipse(in: CGRect(x: dotX - dotR, y: dotY - dotR, width: dotR * 2, height: dotR * 2))
            ctx.setFillColor(CGColor(red: 1.0, green: 0.12, blue: 0.18, alpha: 1))
            ctx.fillPath()

            // Specular highlight on dot
            let hiW = dotR * 0.78, hiH = dotR * 0.50
            ctx.addEllipse(in: CGRect(x: dotX - hiW * 0.40, y: dotY + dotR * 0.12, width: hiW, height: hiH))
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.60))
            ctx.fillPath()

            return true
        }
        NSApp.applicationIconImage = icon
        if let path = Bundle.main.bundlePath as String? {
            NSWorkspace.shared.setIcon(icon, forFile: path, options: [])
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let cfg = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            let icon = NSImage(systemSymbolName: "cursorarrow.rays",
                               accessibilityDescription: "PPT Remote")?
                .withSymbolConfiguration(cfg)
            icon?.isTemplate = true
            button.image = icon
            button.toolTip = "PPT Remote"
        }

        let menu = NSMenu()
        let qrView = QRMenuView()
        let qrItem = NSMenuItem()
        qrItem.view = qrView
        qrItem.tag = 100
        menu.addItem(qrItem)
        menu.addItem(NSMenuItem.separator())
        let copyItem = NSMenuItem(title: "Copy URL", action: #selector(copyURL), keyEquivalent: "c")
        copyItem.target = self
        menu.addItem(copyItem)
        let refreshItem = NSMenuItem(title: "Refresh URL", action: #selector(refreshURL), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
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
        let router = Router(scripts: scripts, mover: mover, token: token)
        do {
            let server = try HTTPServer(port: port, handler: router.handle)
            server.wsHandler = router.handleWS
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
        return "http://\(host):\(port)/\(token)"
    }

    private func updateMenuURL() {
        if let item = statusItem.menu?.item(withTag: 100) {
            if let view = item.view as? QRMenuView {
                view.update(url: currentURL())
            }
        }
    }

    @objc private func refreshURL() {
        updateMenuURL()
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
