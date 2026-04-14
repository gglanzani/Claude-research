import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ImageIO

// MARK: - Export format

enum ExportFormat {
    case png, webp, svg

    var fileExtension: String {
        switch self {
        case .png:  return "png"
        case .webp: return "webp"
        case .svg:  return "svg"
        }
    }

    var utType: UTType {
        switch self {
        case .png:  return .png
        case .webp: return .webP
        case .svg:  return .svg
        }
    }
}

// MARK: - Export manager

@MainActor
enum ExportManager {

    static func export(model: CardModel, size: CGSize, format: ExportFormat) throws -> Data {
        switch format {
        case .png:  return try renderBitmap(model: model, size: size, utType: .png)
        case .webp: return try renderBitmap(model: model, size: size, utType: .webP)
        case .svg:  return try generateSVG(model: model, size: size)
        }
    }

    // MARK: Bitmap (PNG / WebP)

    private static func renderBitmap(model: CardModel, size: CGSize, utType: UTType) throws -> Data {
        let card = CardView(model: model)
            .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 1.0          // already at output resolution

        guard let cgImage = renderer.cgImage else {
            throw ExportError.renderFailed
        }

        let mutableData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
                mutableData,
                utType.identifier as CFString,
                1, nil)
        else { throw ExportError.encodingFailed }

        let props: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.92
        ]
        CGImageDestinationAddImage(dest, cgImage, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw ExportError.encodingFailed
        }
        return mutableData as Data
    }

    // MARK: SVG

    private static func generateSVG(model: CardModel, size: CGSize) throws -> Data {
        let W = size.width
        let H = size.height
        let hPad = max(W * 0.09, 40)

        let bgHex   = model.backgroundColor.toHex() ?? "#0f0f1a"
        let txHex   = model.textColor.toHex() ?? "#ffffff"
        let family  = (model.selectedFont.familyName ?? model.selectedFont.fontName).xmlEscaped
        let qSize   = model.quoteFontSize
        let aSize   = model.authorFontSize
        let lineH   = qSize * 1.45

        // Wrap quote text into lines (approximate — SVG has no native word-wrap).
        let charsPerLine = max(1, Int((W - hPad * 2) / (qSize * 0.52)))
        let wrappedLines = wordWrap(model.quote, charsPerLine: charsPerLine)
        let totalTextH   = CGFloat(wrappedLines.count) * lineH

        // Vertical layout
        let decorH   = model.showDecoration ? qSize * 1.8 : 0
        let ruleGap  = max(H * 0.030, 14)
        let totalH   = decorH + totalTextH + ruleGap * 2 + 1.5 + aSize
        let startY   = (H - totalH) / 2

        var els = [String]()

        // Background
        els.append("<rect width=\"\(iStr(W))\" height=\"\(iStr(H))\" fill=\"\(bgHex)\"/>")

        // Opening quote decoration
        var curY = startY
        if model.showDecoration {
            let dSize = qSize * 2.5
            els.append("""
                <text x="\(fStr(hPad))" y="\(fStr(curY + dSize * 0.72))" \
                font-family="\(family), Georgia, serif" font-size="\(fStr(dSize))" \
                fill="\(txHex)" opacity="0.22" font-weight="bold">\u{201C}</text>
                """)
            curY += decorH
        }

        // Quote lines
        els.append("""
            <text text-anchor="middle" font-family="\(family), Georgia, serif" \
            font-size="\(fStr(qSize))" fill="\(txHex)">
            """)
        for (i, line) in wrappedLines.enumerated() {
            let y  = i == 0 ? curY + qSize : 0.0
            let dy = i == 0 ? 0.0 : lineH
            let attr = i == 0
                ? "x=\"\(fStr(W / 2))\" y=\"\(fStr(y))\""
                : "x=\"\(fStr(W / 2))\" dy=\"\(fStr(dy))\""
            els.append("  <tspan \(attr)>\(line.xmlEscaped)</tspan>")
        }
        els.append("</text>")
        curY += totalTextH

        // Rule
        curY += ruleGap
        let rx = W / 2
        els.append("""
            <line x1="\(fStr(rx - 18))" y1="\(fStr(curY))" \
            x2="\(fStr(rx + 18))" y2="\(fStr(curY))" \
            stroke="\(txHex)" stroke-opacity="0.30" stroke-width="1.5"/>
            """)
        curY += 1.5 + ruleGap

        // Author
        els.append("""
            <text x="\(fStr(W / 2))" y="\(fStr(curY + aSize))" \
            text-anchor="middle" font-family="\(family), Georgia, serif" \
            font-size="\(fStr(aSize))" fill="\(txHex)" opacity="0.82" \
            letter-spacing="1.4">— \(model.author.xmlEscaped)</text>
            """)

        let body = els.joined(separator: "\n  ")
        let svg = """
            <?xml version="1.0" encoding="UTF-8"?>
            <svg xmlns="http://www.w3.org/2000/svg" \
            width="\(iStr(W))" height="\(iStr(H))" \
            viewBox="0 0 \(iStr(W)) \(iStr(H))">
              \(body)
            </svg>
            """

        guard let data = svg.data(using: .utf8) else {
            throw ExportError.encodingFailed
        }
        return data
    }

    // MARK: - Helpers

    private static func wordWrap(_ text: String, charsPerLine: Int) -> [String] {
        let words = text.split(separator: " ").map(String.init)
        var lines  = [String]()
        var line   = ""
        for word in words {
            if line.isEmpty {
                line = word
            } else if line.count + 1 + word.count <= charsPerLine {
                line += " " + word
            } else {
                lines.append(line)
                line = word
            }
        }
        if !line.isEmpty { lines.append(line) }
        return lines.isEmpty ? [""] : lines
    }

    private static func fStr(_ v: CGFloat) -> String { String(format: "%.2f", v) }
    private static func iStr(_ v: CGFloat) -> String { String(Int(v.rounded())) }
}

// MARK: - Errors

enum ExportError: LocalizedError {
    case renderFailed, encodingFailed

    var errorDescription: String? {
        switch self {
        case .renderFailed:   return "Failed to render the card. Make sure the window is visible."
        case .encodingFailed: return "Failed to encode the image data."
        }
    }
}
