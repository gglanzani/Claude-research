import SwiftUI

struct PalettePickerView: View {
    @ObservedObject var state: CardState
    @State private var hexBackground: String = ""
    @State private var hexForeground: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Color Palette", systemImage: "paintpalette")
                .font(.headline)

            // Preset swatches
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(ColorPalette.presets) { palette in
                    PaletteSwatchView(palette: palette, isSelected: !state.useCustomColors && state.selectedPalette.id == palette.id)
                        .onTapGesture {
                            state.useCustomColors = false
                            state.selectedPalette = palette
                        }
                }
            }

            Divider()

            // Custom colors
            Toggle("Custom Colors", isOn: $state.useCustomColors)
                .toggleStyle(.switch)

            if state.useCustomColors {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("Background")
                            .foregroundStyle(.secondary)
                        ColorPicker("", selection: $state.customBackground, supportsOpacity: false)
                            .labelsHidden()
                        TextField("Hex", text: $hexBackground)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 80)
                            .onSubmit { applyHex(hexBackground) { state.customBackground = $0 } }
                    }
                    GridRow {
                        Text("Foreground")
                            .foregroundStyle(.secondary)
                        ColorPicker("", selection: $state.customForeground, supportsOpacity: false)
                            .labelsHidden()
                        TextField("Hex", text: $hexForeground)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 80)
                            .onSubmit { applyHex(hexForeground) { state.customForeground = $0 } }
                    }
                }
                .onChange(of: state.customBackground) {
                    hexBackground = state.customBackground.hexString
                }
                .onChange(of: state.customForeground) {
                    hexForeground = state.customForeground.hexString
                }
                .onAppear {
                    hexBackground = state.customBackground.hexString
                    hexForeground = state.customForeground.hexString
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func applyHex(_ hex: String, apply: (Color) -> Void) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count >= 6 {
            apply(Color(hex: cleaned))
        }
    }
}

struct PaletteSwatchView: View {
    let palette: ColorPalette
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(palette.background)
                    .frame(height: 36)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)

                HStack(spacing: 3) {
                    Circle().fill(palette.foreground).frame(width: 8, height: 8)
                    Circle().fill(palette.accentColor).frame(width: 8, height: 8)
                }
            }
            Text(palette.name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .cursor(.pointingHand)
    }
}

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}
