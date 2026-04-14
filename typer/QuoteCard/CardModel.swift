import SwiftUI
import AppKit

// MARK: - Card Aspect Ratio

enum CardAspectRatio: String, CaseIterable, Identifiable {
    case square    = "1:1"
    case landscape = "16:9"
    case portrait  = "4:5"
    case story     = "9:16"

    var id: String { rawValue }

    /// Full-resolution output dimensions in pixels.
    var outputSize: CGSize {
        switch self {
        case .square:    return CGSize(width: 1080, height: 1080)
        case .landscape: return CGSize(width: 1920, height: 1080)
        case .portrait:  return CGSize(width: 1080, height: 1350)
        case .story:     return CGSize(width: 1080, height: 1920)
        }
    }

    var aspectRatio: CGFloat {
        let s = outputSize
        return s.width / s.height
    }
}

// MARK: - Color Palette

struct ColorPalette: Identifiable {
    let id = UUID()
    let name: String
    let background: Color
    let text: Color

    static let all: [ColorPalette] = [
        .init(name: "Midnight",  background: Color(hex: "0f0f1a"), text: Color(hex: "ffffff")),
        .init(name: "Paper",     background: Color(hex: "f8f4ec"), text: Color(hex: "2c1810")),
        .init(name: "Slate",     background: Color(hex: "1e293b"), text: Color(hex: "f1f5f9")),
        .init(name: "Sage",      background: Color(hex: "2d4a3e"), text: Color(hex: "d4edda")),
        .init(name: "Mauve",     background: Color(hex: "6b4f6b"), text: Color(hex: "fae5d3")),
        .init(name: "Copper",    background: Color(hex: "1c1c1c"), text: Color(hex: "c87533")),
        .init(name: "Fog",       background: Color(hex: "e8e8e8"), text: Color(hex: "2c2c2c")),
        .init(name: "Twilight",  background: Color(hex: "2c3e50"), text: Color(hex: "ecf0f1")),
        .init(name: "Rose",      background: Color(hex: "fce4ec"), text: Color(hex: "880e4f")),
        .init(name: "Amber",     background: Color(hex: "fff8e1"), text: Color(hex: "5d4037")),
        .init(name: "Obsidian",  background: Color(hex: "16213e"), text: Color(hex: "e2d9c9")),
        .init(name: "Teal",      background: Color(hex: "004d40"), text: Color(hex: "e0f2f1")),
    ]
}

// MARK: - Card Model

final class CardModel: ObservableObject {
    @Published var quote: String = "The only way to do great work is to love what you do."
    @Published var author: String = "Steve Jobs"

    /// The NSFont selected via the font panel (family + style).
    @Published var selectedFont: NSFont = NSFont(name: "Georgia", size: 32)
        ?? NSFont.systemFont(ofSize: 32, weight: .regular)

    @Published var backgroundColor: Color = ColorPalette.all[0].background
    @Published var textColor: Color       = ColorPalette.all[0].text

    @Published var aspectRatio: CardAspectRatio = .square

    /// Size of the main quote text (pt).
    @Published var quoteFontSize: CGFloat  = 28
    /// Size of the author attribution text (pt).
    @Published var authorFontSize: CGFloat = 16

    /// Whether to show the decorative opening quotation mark.
    @Published var showDecoration: Bool = true

    // Convenience: PostScript name used by Font.custom
    var fontPostScriptName: String { selectedFont.fontName }
    var fontDisplayName: String    { selectedFont.displayName ?? selectedFont.familyName ?? selectedFont.fontName }
}

// MARK: - Color + Hex

extension Color {
    /// Initialise from a 6-digit hex string (with or without leading "#").
    init(hex: String) {
        let raw = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#").union(.whitespaces))
        var value: UInt64 = 0
        Scanner(string: raw).scanHexInt64(&value)

        let r, g, b: UInt64
        switch raw.count {
        case 3:
            (r, g, b) = ((value >> 8) * 17, (value >> 4 & 0xF) * 17, (value & 0xF) * 17)
        case 6:
            (r, g, b) = (value >> 16, value >> 8 & 0xFF, value & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }

        self.init(.sRGB,
                  red:   Double(r) / 255,
                  green: Double(g) / 255,
                  blue:  Double(b) / 255,
                  opacity: 1)
    }

    /// Returns a "#rrggbb" string, or nil if the color cannot be resolved.
    func toHex() -> String? {
        guard let cgColor = cgColor,
              let comps = cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             intent: .defaultIntent,
                                             options: nil)?.components,
              comps.count >= 3
        else { return nil }

        let r = Int((comps[0] * 255).rounded())
        let g = Int((comps[1] * 255).rounded())
        let b = Int((comps[2] * 255).rounded())
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}

// MARK: - String + XML escape

extension String {
    var xmlEscaped: String {
        self
            .replacingOccurrences(of: "&",  with: "&amp;")
            .replacingOccurrences(of: "<",  with: "&lt;")
            .replacingOccurrences(of: ">",  with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'",  with: "&apos;")
    }
}
