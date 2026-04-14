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
            exportBitmap(state: state, url: url, format: .png)
        case .webp:
            exportBitmap(state: state, url: url, format: .png) // fallback: macOS doesn't natively encode WebP
            // Convert with sips if available
            convertToWebP(from: url)
        case .svg:
            exportSVG(state: state, url: url)
        }
    }

    private static func exportBitmap(state: CardState, url: URL, format: NSBitmapImageRep.FileType) {
        let scale: CGFloat = 2.0 // Retina quality
        let size = CGSize(width: state.selectedSize.width, height: state.selectedSize.height)

        let hostingView = NSHostingView(rootView: ExportableCardView(state: state))
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.layout()

        guard let bitmapRep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else { return }
        bitmapRep.size = CGSize(width: size.width * scale, height: size.height * scale)
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmapRep)

        // Scale up for HiDPI
        let image = NSImage(size: CGSize(width: size.width * scale, height: size.height * scale))
        image.addRepresentation(bitmapRep)

        if let data = bitmapRep.representation(using: format, properties: [.compressionFactor: 0.95]) {
            try? data.write(to: url)
        }
    }

    private static func convertToWebP(from url: URL) {
        // sips on macOS can convert to webp on macOS 14+
        let task = Process()
        task.launchPath = "/usr/bin/sips"
        task.arguments = ["-s", "format", "webp", url.path, "--out", url.path]
        try? task.run()
        task.waitUntilExit()
    }

    private static func exportSVG(state: CardState, url: URL) {
        let svg = buildSVG(state: state)
        try? svg.write(to: url, atomically: true, encoding: .utf8)
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

        // Estimate line breaks
        let avgCharWidth = state.quoteFontSize * 0.55
        let charsPerLine = max(1, Int(CGFloat(availableWidth) / avgCharWidth))
        let wrappedLines = wrapText(quoteText, charsPerLine: charsPerLine)

        let quoteLineHeight = state.quoteFontSize + state.lineSpacing
        let quoteTotalHeight = CGFloat(wrappedLines.count) * quoteLineHeight

        let startY = CGFloat(h) / 2 - quoteTotalHeight / 2 - state.authorFontSize / 2

        var linesXML = ""
        for (i, line) in wrappedLines.enumerated() {
            let dy = i == 0 ? "0" : "\(Int(quoteLineHeight))"
            linesXML += """
            <tspan x="\(textX)" dy="\(dy)">\(line)</tspan>
            """
        }

        let authorY = Int(startY + quoteTotalHeight + state.authorSpacing)
        var dashLine = ""
        if state.quoteDecoration == .dash {
            let dashX = textX - 22
            dashLine = """
            <line x1="\(dashX - 16)" y1="\(authorY - Int(state.authorFontSize) / 3)" x2="\(dashX)" y2="\(authorY - Int(state.authorFontSize) / 3)" stroke="\(accentHex)" stroke-width="1.5"/>
            """
        }

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="\(w)" height="\(h)" viewBox="0 0 \(w) \(h)">
          <rect width="\(w)" height="\(h)" fill="\(bgHex)"/>
          <text
            x="\(textX)"
            y="\(Int(startY))"
            font-family="\(state.quoteFontName), Georgia, serif"
            font-size="\(Int(state.quoteFontSize))"
            font-style="\(quoteFontStyle)"
            font-weight="\(quoteFontWeight)"
            fill="\(fgHex)"
            text-anchor="\(textAnchor)"
            letter-spacing="\(Int(state.letterSpacing))"
          >\(linesXML)</text>
          \(dashLine)
          <text
            x="\(textX)"
            y="\(authorY)"
            font-family="\(state.authorFontName), Helvetica Neue, sans-serif"
            font-size="\(Int(state.authorFontSize))"
            font-weight="\(authorFontWeight)"
            fill="\(accentHex)"
            text-anchor="\(textAnchor)"
            letter-spacing="1.5"
          >\(authorText)</text>
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
        // Simple greedy word wrap
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
