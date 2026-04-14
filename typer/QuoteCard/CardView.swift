import SwiftUI

/// The actual card artwork — used both for live preview and for export rendering.
struct CardView: View {
    let model: CardModel

    var body: some View {
        GeometryReader { geo in
            ZStack {
                model.backgroundColor

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    content(in: geo.size)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Inner layout

    @ViewBuilder
    private func content(in size: CGSize) -> some View {
        let hPad  = max(size.width  * 0.09, 40)
        let vPad  = max(size.height * 0.09, 32)
        let lineH = model.quoteFontSize * 0.30   // extra line-spacing

        VStack(alignment: .center, spacing: 0) {

            // Decorative opening quote mark
            if model.showDecoration {
                Text("\u{201C}")
                    .font(quoteFont(size: model.quoteFontSize * 2.8))
                    .foregroundStyle(model.textColor.opacity(0.22))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, -(model.quoteFontSize * 1.6))
            }

            // Main quote
            Text(model.quote)
                .font(quoteFont(size: model.quoteFontSize))
                .foregroundStyle(model.textColor)
                .multilineTextAlignment(.center)
                .lineSpacing(lineH)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, model.showDecoration ? 0 : 0)

            // Rule separator
            Rectangle()
                .fill(model.textColor.opacity(0.30))
                .frame(width: 36, height: 1.5)
                .padding(.vertical, max(size.height * 0.030, 14))

            // Author attribution
            Text("— \(model.author)")
                .font(authorFont(size: model.authorFontSize))
                .foregroundStyle(model.textColor.opacity(0.82))
                .tracking(1.4)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, hPad)
        .padding(.vertical,   vPad)
    }

    // MARK: - Font helpers

    /// Build a SwiftUI Font from the user-selected NSFont at the requested point size.
    private func quoteFont(size: CGFloat) -> Font {
        Font.custom(model.fontPostScriptName, size: size)
    }

    private func authorFont(size: CGFloat) -> Font {
        // Try a condensed / light variant of the same family for the attribution;
        // fall back to the same face if the variant doesn't exist.
        Font.custom(model.fontPostScriptName, size: size)
    }
}
