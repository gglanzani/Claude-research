import SwiftUI
import AppKit

// MARK: - Color Palette

struct ColorPalette: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let background: Color
    let foreground: Color
    let accentColor: Color

    static let presets: [ColorPalette] = [
        ColorPalette(name: "Midnight", background: Color(hex: "#0D1117"), foreground: Color(hex: "#E6EDF3"), accentColor: Color(hex: "#58A6FF")),
        ColorPalette(name: "Ivory", background: Color(hex: "#FAFAF8"), foreground: Color(hex: "#1A1A1A"), accentColor: Color(hex: "#C8A96E")),
        ColorPalette(name: "Slate", background: Color(hex: "#1E293B"), foreground: Color(hex: "#F1F5F9"), accentColor: Color(hex: "#94A3B8")),
        ColorPalette(name: "Blush", background: Color(hex: "#FDF2F8"), foreground: Color(hex: "#4A1942"), accentColor: Color(hex: "#DB2777")),
        ColorPalette(name: "Forest", background: Color(hex: "#064E3B"), foreground: Color(hex: "#ECFDF5"), accentColor: Color(hex: "#6EE7B7")),
        ColorPalette(name: "Ochre", background: Color(hex: "#78350F"), foreground: Color(hex: "#FFFBEB"), accentColor: Color(hex: "#FCD34D")),
        ColorPalette(name: "Lavender", background: Color(hex: "#EDE9FE"), foreground: Color(hex: "#2E1065"), accentColor: Color(hex: "#7C3AED")),
        ColorPalette(name: "Storm", background: Color(hex: "#374151"), foreground: Color(hex: "#F9FAFB"), accentColor: Color(hex: "#9CA3AF")),
        ColorPalette(name: "Rose Gold", background: Color(hex: "#FFF1F2"), foreground: Color(hex: "#881337"), accentColor: Color(hex: "#F43F5E")),
        ColorPalette(name: "Denim", background: Color(hex: "#1E3A5F"), foreground: Color(hex: "#EFF6FF"), accentColor: Color(hex: "#60A5FA")),
        ColorPalette(name: "Sage", background: Color(hex: "#F0FDF4"), foreground: Color(hex: "#14532D"), accentColor: Color(hex: "#4ADE80")),
        ColorPalette(name: "Charcoal", background: Color(hex: "#292524"), foreground: Color(hex: "#FAFAF9"), accentColor: Color(hex: "#A8A29E")),
    ]
}

// MARK: - Card Size

struct CardSize: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let width: CGFloat
    let height: CGFloat
    var aspectLabel: String { "\(Int(width))×\(Int(height))" }

    static let presets: [CardSize] = [
        CardSize(name: "Instagram Square", width: 1080, height: 1080),
        CardSize(name: "Instagram Story", width: 1080, height: 1920),
        CardSize(name: "Twitter/X Post", width: 1200, height: 675),
        CardSize(name: "Facebook Post", width: 1200, height: 630),
        CardSize(name: "LinkedIn Post", width: 1200, height: 627),
        CardSize(name: "Pinterest Pin", width: 1000, height: 1500),
        CardSize(name: "A4 Landscape", width: 2480, height: 1748),
    ]

    static let `default` = presets[0]
}

// MARK: - Quote Style

enum QuoteDecoration: String, CaseIterable, Identifiable {
    case none = "None"
    case quotationMarks = "Quotation Marks"
    case openingMark = "Opening Mark"
    case dash = "Em Dash"
    case ornament = "Ornament"

    var id: String { rawValue }
}

// MARK: - Text Alignment

enum CardTextAlignment: String, CaseIterable, Identifiable {
    case leading = "Left"
    case center = "Center"
    case trailing = "Right"

    var id: String { rawValue }

    var textAlignment: TextAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    var multilineAlignment: NSTextAlignment {
        switch self {
        case .leading: return .left
        case .center: return .center
        case .trailing: return .right
        }
    }
}

// MARK: - Card State

class CardState: ObservableObject {
    @Published var quote: String = "The only way to do great work is to love what you do."
    @Published var author: String = "Steve Jobs"
    @Published var selectedPalette: ColorPalette = ColorPalette.presets[0]
    @Published var useCustomColors: Bool = false
    @Published var customBackground: Color = .black
    @Published var customForeground: Color = .white
    @Published var quoteFontName: String = "Georgia"
    @Published var authorFontName: String = "Helvetica Neue"
    @Published var quoteFontSize: CGFloat = 52
    @Published var authorFontSize: CGFloat = 22
    @Published var selectedSize: CardSize = CardSize.default
    @Published var textAlignment: CardTextAlignment = .center
    @Published var quoteDecoration: QuoteDecoration = .quotationMarks
    @Published var padding: CGFloat = 80
    @Published var lineSpacing: CGFloat = 8
    @Published var authorSpacing: CGFloat = 32
    @Published var showAuthorLine: Bool = true
    @Published var italicizeQuote: Bool = true
    @Published var boldAuthor: Bool = false
    @Published var letterSpacing: CGFloat = 0

    var effectiveBackground: Color {
        useCustomColors ? customBackground : selectedPalette.background
    }

    var effectiveForeground: Color {
        useCustomColors ? customForeground : selectedPalette.foreground
    }

    var effectiveAccent: Color {
        useCustomColors ? customForeground.opacity(0.5) : selectedPalette.accentColor
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }

    var hexString: String {
        let nsColor = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        let r = Int((nsColor.redComponent * 255).rounded())
        let g = Int((nsColor.greenComponent * 255).rounded())
        let b = Int((nsColor.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
