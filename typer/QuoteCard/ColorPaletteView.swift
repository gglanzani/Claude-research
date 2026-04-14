import SwiftUI

/// A grid of colour-pair swatches. Each swatch shows the background colour in the
/// upper-left triangle and the text colour in the lower-right triangle.
struct ColorPaletteView: View {
    var onSelect: (ColorPalette) -> Void

    private let columns = [GridItem(.adaptive(minimum: 40, maximum: 52), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(ColorPalette.all) { palette in
                SwatchView(palette: palette) { onSelect(palette) }
            }
        }
    }
}

// MARK: - Individual swatch

private struct SwatchView: View {
    let palette: ColorPalette
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // Background fill
                RoundedRectangle(cornerRadius: 8)
                    .fill(palette.background)

                // Text colour shown as bottom-right triangle
                RoundedRectangle(cornerRadius: 8)
                    .fill(palette.text)
                    .mask(
                        GeometryReader { g in
                            LowerTriangle()
                                .frame(width: g.size.width, height: g.size.height)
                        }
                    )

                // Hover ring
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isHovered ? Color.primary.opacity(0.5) : Color.clear,
                        lineWidth: 2
                    )
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .help(palette.name)
        .onHover { isHovered = $0 }
        .accessibilityLabel(palette.name)
    }
}

// MARK: - Lower-right triangle mask

private struct LowerTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to:    CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
