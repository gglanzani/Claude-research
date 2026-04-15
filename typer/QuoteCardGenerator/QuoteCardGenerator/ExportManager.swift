import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case png = "PNG"
    case webp = "WebP"
    case svg = "SVG"

    var id: String { rawValue }
    var fileExtension: String { rawValue.lowercased() }
    var utType: UTType {
        switch self {
        case .png: return .png
        case .webp: return UTType(filenameExtension: "webp") ?? .png
        case .svg: return .svg
        }
    }
}

@MainActor
class ExportManager {
    static func export(state: CardState, format: ExportFormat) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "quote-card.\(format.fileExtension)"
        panel.allowedContentTypes = [format.utType]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        switch format {
        case .png:
            if let data = renderBitmapData(state: state, fileType: .png) {
                try? data.write(to: url)
            }
        case .webp:
            exportWebP(state: state, to: url)
        case .svg:
            let svg = buildSVG(state: state)
            try? svg.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Bitmap rendering (correct 2× HiDPI)

    private static func renderBitmapData(state: CardState, fileType: NSBitmapImageRep.FileType) -> Data? {
        let w = Int(state.selectedSize.width)
        let h = Int(state.selectedSize.height)
        let scale = 2

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: w * scale,
            height: h * scale,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))

        let hostingView = NSHostingView(rootView: ExportableCardView(state: state))
        hostingView.frame = CGRect(origin: .zero, size: CGSize(width: w, height: h))
        hostingView.layout()

        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        hostingView.displayIgnoringOpacity(hostingView.bounds, in: nsCtx)
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = CGSize(width: w, height: h)     // set logical points size for metadata
        return rep.representation(using: fileType, properties: [.compressionFactor: 0.95])
    }

    // MARK: - WebP via sips (macOS 14+)
    // Write PNG to a temp file, then let sips convert it to the final destination.

    private static func exportWebP(state: CardState, to destination: URL) {
        guard let pngData = renderBitmapData(state: state, fileType: .png) else { return }

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")

        do {
            try pngData.write(to: tmp)
        } catch {
            return
        }
        defer { try? FileManager.default.removeItem(at: tmp) }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        task.arguments = [
            "-s", "format", "webp",
            tmp.path,
            "--out", destination.path
        ]
        try? task.run()
        task.waitUntilExit()

        // If sips didn't produce the file (older macOS / failure), fall back to PNG
        if !FileManager.default.fileExists(atPath: destination.path) {
            try? pngData.write(to: destination)
        }
    }

    // MARK: - SVG Builder

    static func buildSVG(state: CardState) -> String {
        let w = Int(state.selectedSize.width)
        let h = Int(state.selectedSize.height)
        let bgHex = state.effectiveBackground.hexString
        let fgHex = state.effectiveForeground.hexString
        let accentHex = state.effectiveAccent.hexString

        let padding = Int(state.padding)
        let availableWidth = w - padding * 2

        let quoteFontStyle = state.italicizeQuote ? "italic" : "normal"
        let quoteFontWeight = "normal"
        let authorFontWeight = state.boldAuthor ? "bold" : "normal"

        let quoteText = decoratedQuote(state: state)
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")

        let authorText = state.author.uppercased()
            .replacingOccurrences(of: "&", with: "&amp;")

        let textAnchor: String
        switch state.textAlignment {
        case .leading: textAnchor = "start"
        case .center: textAnchor = "middle"
        case .trailing: textAnchor = "end"
        }

        let textX: Int
        switch state.textAlignment {
        case .leading: textX = padding
        case .center: textX = w / 2
        case .trailing: textX = w - padding
        }

        let avgCharWidth = state.quoteFontSize * 0.55
        let charsPerLine = max(1, Int(CGFloat(availableWidth) / avgCharWidth))
        let wrappedLines = wrapText(quoteText, charsPerLine: charsPerLine)

        let quoteLineHeight = state.quoteFontSize + state.lineSpacing
        let quoteTotalHeight = CGFloat(wrappedLines.count) * quoteLineHeight
        let startY = CGFloat(h) / 2 - quoteTotalHeight / 2 - state.authorFontSize / 2

        var linesXML = ""
        for (i, line) in wrappedLines.enumerated() {
            let dy = i == 0 ? "0" : "\(Int(quoteLineHeight))"
            linesXML += "<tspan x=\"\(textX)\" dy=\"\(dy)\">\(line)</tspan>"
        }

        let authorY = Int(startY + quoteTotalHeight + state.authorSpacing)
        var dashLine = ""
        if state.quoteDecoration == .dash {
            let dashX = textX - 22
            dashLine = "<line x1=\"\(dashX - 16)\" y1=\"\(authorY - Int(state.authorFontSize) / 3)\" x2=\"\(dashX)\" y2=\"\(authorY - Int(state.authorFontSize) / 3)\" stroke=\"\(accentHex)\" stroke-width=\"1.5\"/>"
        }

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="\(w)" height="\(h)" viewBox="0 0 \(w) \(h)">
          <rect width="\(w)" height="\(h)" fill="\(bgHex)"/>
          <text x="\(textX)" y="\(Int(startY))" font-family="\(state.quoteFontName), Georgia, serif" font-size="\(Int(state.quoteFontSize))" font-style="\(quoteFontStyle)" font-weight="\(quoteFontWeight)" fill="\(fgHex)" text-anchor="\(textAnchor)" letter-spacing="\(Int(state.letterSpacing))">\(linesXML)</text>
          \(dashLine)
          <text x="\(textX)" y="\(authorY)" font-family="\(state.authorFontName), Helvetica Neue, sans-serif" font-size="\(Int(state.authorFontSize))" font-weight="\(authorFontWeight)" fill="\(accentHex)" text-anchor="\(textAnchor)" letter-spacing="1.5">\(authorText)</text>
        </svg>
        """
    }

    private static func decoratedQuote(state: CardState) -> String {
        switch state.quoteDecoration {
        case .none: return state.quote
        case .quotationMarks: return "\u{201C}\(state.quote)\u{201D}"
        case .openingMark: return "\u{201C}\(state.quote)"
        case .dash: return state.quote
        case .ornament: return "\u{2767}  \(state.quote)  \u{2767}"
        }
    }

    private static func wrapText(_ text: String, charsPerLine: Int) -> [String] {
        let words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var lines: [String] = []
        var current = ""
        for word in words {
            if current.isEmpty {
                current = word
            } else if (current + " " + word).count <= charsPerLine {
                current += " " + word
            } else {
                lines.append(current)
                current = word
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }
}
