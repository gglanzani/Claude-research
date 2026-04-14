import SwiftUI
import AppKit

struct CardPreviewView: View {
    @ObservedObject var state: CardState
    var isExport: Bool = false

    private var scaleFactor: CGFloat {
        isExport ? 1.0 : 0.35
    }

    var body: some View {
        ZStack {
            state.effectiveBackground
                .ignoresSafeArea()

            cardContent
                .padding(state.padding * scaleFactor)
        }
        .frame(
            width: state.selectedSize.width * scaleFactor,
            height: state.selectedSize.height * scaleFactor
        )
        .clipShape(RoundedRectangle(cornerRadius: isExport ? 0 : 8))
    }

    @ViewBuilder
    private var cardContent: some View {
        VStack(alignment: alignmentFromState, spacing: state.authorSpacing * scaleFactor) {
            // Quote text
            quoteText

            // Author line
            if state.showAuthorLine && !state.author.isEmpty {
                authorText
            }
        }
    }

    private var alignmentFromState: HorizontalAlignment {
        switch state.textAlignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private var decoratedQuote: String {
        switch state.quoteDecoration {
        case .none:
            return state.quote
        case .quotationMarks:
            return "\u{201C}\(state.quote)\u{201D}"
        case .openingMark:
            return "\u{201C}\(state.quote)"
        case .dash:
            return state.quote
        case .ornament:
            return "\u{2767}  \(state.quote)  \u{2767}"
        }
    }

    @ViewBuilder
    private var quoteText: some View {
        let font = resolveFont(name: state.quoteFontName,
                               size: state.quoteFontSize * scaleFactor,
                               italic: state.italicizeQuote,
                               bold: false)
        Text(decoratedQuote)
            .font(.custom(state.quoteFontName, size: state.quoteFontSize * scaleFactor))
            .italic(state.italicizeQuote)
            .tracking(state.letterSpacing * scaleFactor)
            .lineSpacing(state.lineSpacing * scaleFactor)
            .multilineTextAlignment(state.textAlignment.textAlignment)
            .foregroundColor(state.effectiveForeground)
            .fixedSize(horizontal: false, vertical: true)
            .id(font.description) // force redraw on font change
    }

    @ViewBuilder
    private var authorText: some View {
        HStack(spacing: 12 * scaleFactor) {
            if state.quoteDecoration == .dash {
                Rectangle()
                    .frame(width: 32 * scaleFactor, height: 1.5 * scaleFactor)
                    .foregroundColor(state.effectiveAccent)
            }
            Text(state.author)
                .font(.custom(state.authorFontName, size: state.authorFontSize * scaleFactor))
                .bold(state.boldAuthor)
                .tracking(1.5 * scaleFactor)
                .foregroundColor(state.effectiveAccent)
                .textCase(.uppercase)
        }
    }

    private func resolveFont(name: String, size: CGFloat, italic: Bool, bold: Bool) -> NSFont {
        var descriptor = NSFontDescriptor(name: name, size: size)
        var traits: NSFontDescriptor.SymbolicTraits = []
        if italic { traits.insert(.italic) }
        if bold { traits.insert(.bold) }
        if !traits.isEmpty {
            descriptor = descriptor.withSymbolicTraits(traits)
        }
        return NSFont(descriptor: descriptor, size: size) ?? NSFont.systemFont(ofSize: size)
    }
}

// MARK: - Renderable card for export

struct ExportableCardView: View {
    @ObservedObject var state: CardState

    var body: some View {
        CardPreviewView(state: state, isExport: true)
    }
}
