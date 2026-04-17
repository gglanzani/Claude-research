import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CoreText

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
    static func copyToClipboard(state: CardState) {
        guard let data = renderBitmapData(state: state, fileType: .png),
              let image = NSImage(data: data) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

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

    // MARK: - Bitmap rendering

    private static func renderBitmapData(state: CardState, fileType: NSBitmapImageRep.FileType) -> Data? {
        let w = Int(state.selectedSize.width)
        let h = Int(state.selectedSize.height)
        let scale = 1

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
        rep.size = CGSize(width: w, height: h)
        return rep.representation(using: fileType, properties: [.compressionFactor: 0.95])
    }

    // MARK: - WebP via cwebp

    private static func exportWebP(state: CardState, to destination: URL) {
        guard let pngData = renderBitmapData(state: state, fileType: .png) else { return }

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        do { try pngData.write(to: tmp) } catch { return }
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Prefer cwebp (Homebrew) for quality control; fall back to sips.
        let cwebp = "/opt/homebrew/bin/cwebp"
        if FileManager.default.isExecutableFile(atPath: cwebp) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: cwebp)
            task.arguments = ["-q", "100", "-quiet", tmp.path, "-o", destination.path]
            try? task.run()
            task.waitUntilExit()
        } else {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
            task.arguments = ["-s", "format", "webp", "-s", "formatOptions", "85",
                              tmp.path, "--out", destination.path]
            try? task.run()
            task.waitUntilExit()
        }

        if !FileManager.default.fileExists(atPath: destination.path) {
            try? pngData.write(to: destination)
        }
    }

    // MARK: - Font embedding helpers

    /// Locates the font file for the given name+traits via CoreText.
    private static func fontFileURL(name: String, italic: Bool, bold: Bool) -> URL? {
        var descriptor = CTFontDescriptorCreateWithNameAndSize(name as CFString, 12)
        var symbolicTraits: CTFontSymbolicTraits = []
        if italic { symbolicTraits.insert(.traitItalic) }
        if bold   { symbolicTraits.insert(.traitBold) }
        if !symbolicTraits.isEmpty {
            descriptor = CTFontDescriptorCreateCopyWithAttributes(descriptor,
                [kCTFontTraitsAttribute: [kCTFontSymbolicTrait: symbolicTraits.rawValue]] as CFDictionary)
        }
        guard let urlRef = CTFontDescriptorCopyAttribute(descriptor, kCTFontURLAttribute) else { return nil }
        return urlRef as? URL
    }

    /// Subsets the font at `url` to only the glyphs in `text` using fonttools (Python).
    /// Falls back to the full font if fonttools is unavailable.
    private static func subsetFontData(url: URL, text: String) -> Data? {
        // Inline Python script: reads font path + text from argv, writes subset bytes to stdout.
        let script = """
import sys, io
from fontTools import subset as ft_subset
options = ft_subset.Options()
options.layout_features = []
tt = ft_subset.load_font(sys.argv[1], options)
s = ft_subset.Subsetter(options=options)
s.populate(text=sys.argv[2])
s.subset(tt)
buf = io.BytesIO()
ft_subset.save_font(tt, buf, options)
sys.stdout.buffer.write(buf.getvalue())
"""
        // Find python3 — prefer Homebrew, fall back to system.
        let candidates = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
        guard let python = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return try? Data(contentsOf: url)   // full font fallback
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: python)
        task.arguments = ["-c", script, url.path, text]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()   // suppress fonttools warnings

        do { try task.run() } catch { return try? Data(contentsOf: url) }
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        // If subsetting produced nothing (e.g. fonttools not installed), use full font.
        return data.isEmpty ? (try? Data(contentsOf: url)) : data
    }

    /// Builds a `<style>` block with subset @font-face rules for quote and author fonts.
    private static func fontFaceStyle(state: CardState) -> String {
        // Collect all characters that will appear in the SVG.
        let quoteChars = decoratedQuote(state: state)
        let authorChars = state.author.uppercased()
        let allText = quoteChars + authorChars

        var rules = ""

        func addRule(family: String, italic: Bool, bold: Bool) {
            guard let url = fontFileURL(name: family, italic: italic, bold: bold),
                  let data = subsetFontData(url: url, text: allText) else { return }

            let ext = url.pathExtension.lowercased()
            let mime: String
            switch ext {
            case "otf":   mime = "font/opentype"
            case "woff":  mime = "font/woff"
            case "woff2": mime = "font/woff2"
            default:      mime = "font/truetype"
            }
            let style  = italic ? "italic" : "normal"
            let weight = bold   ? "bold"   : "normal"
            rules += """
              @font-face {
                font-family: '\(family)';
                font-style: \(style);
                font-weight: \(weight);
                src: url('data:\(mime);base64,\(data.base64EncodedString())');
              }\n
            """
        }

        addRule(family: state.quoteFontName,  italic: state.italicizeQuote, bold: false)
        addRule(family: state.authorFontName, italic: false, bold: state.boldAuthor)

        return rules.isEmpty ? "" : "  <style>\n\(rules)  </style>"
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

        let fontStyle = fontFaceStyle(state: state)

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="\(w)" height="\(h)" viewBox="0 0 \(w) \(h)">
        \(fontStyle)
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
