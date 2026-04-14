import SwiftUI
import AppKit

struct ControlsView: View {
    @EnvironmentObject var model: CardModel

    // Local hex-field state; synced from model on palette/picker changes.
    @State private var bgHex:   String = ColorPalette.all[0].background.toHex() ?? "#0f0f1a"
    @State private var textHex: String = ColorPalette.all[0].text.toHex() ?? "#ffffff"

    @FocusState private var focus: Field?

    enum Field: Hashable { case quote, author, bgHex, textHex }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 18) {

                // MARK: Quote text
                sectionLabel("Quote")
                TextEditor(text: $model.quote)
                    .font(.body)
                    .frame(minHeight: 80, maxHeight: 130)
                    .focused($focus, equals: .quote)
                    .overlay(fieldBorder(focus == .quote))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(.top, 2)

                // MARK: Author
                sectionLabel("Author")
                TextField("Author name", text: $model.author)
                    .textFieldStyle(.plain)
                    .padding(7)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(fieldBorder(focus == .author))
                    .focused($focus, equals: .author)
                    .onSubmit { focus = nil }

                Divider()

                // MARK: Font
                sectionLabel("Font")
                FontPickerButton(font: $model.selectedFont)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // MARK: Font sizes
                sectionLabel("Size")
                VStack(spacing: 8) {
                    sizeRow(label: "Quote",  value: $model.quoteFontSize,  range: 14...72)
                    sizeRow(label: "Author", value: $model.authorFontSize, range: 10...36)
                }

                Divider()

                // MARK: Palette presets
                sectionLabel("Palette")
                ColorPaletteView { palette in
                    model.backgroundColor = palette.background
                    model.textColor       = palette.text
                    bgHex   = palette.background.toHex() ?? bgHex
                    textHex = palette.text.toHex() ?? textHex
                }

                // MARK: Custom colours
                sectionLabel("Custom Colors")
                HStack(alignment: .top, spacing: 20) {
                    colorField(label: "Background",
                               color: $model.backgroundColor,
                               hex:   $bgHex,
                               focusTag: .bgHex)
                    colorField(label: "Text",
                               color: $model.textColor,
                               hex:   $textHex,
                               focusTag: .textHex)
                }

                Divider()

                // MARK: Aspect ratio
                sectionLabel("Aspect Ratio")
                Picker("", selection: $model.aspectRatio) {
                    ForEach(CardAspectRatio.allCases) { ratio in
                        Text(ratio.rawValue).tag(ratio)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                // MARK: Decoration toggle
                Toggle("Opening quotation mark", isOn: $model.showDecoration)
                    .toggleStyle(.switch)

                Spacer(minLength: 16)
            }
            .padding(16)
        }
        // Keep hex fields in sync when model changes externally
        .onChange(of: model.backgroundColor) { bgHex   = $0.toHex() ?? bgHex }
        .onChange(of: model.textColor)       { textHex = $0.toHex() ?? textHex }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(.primary)
    }

    @ViewBuilder
    private func sizeRow(label: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 52, alignment: .leading)
                .foregroundStyle(.secondary)
            Slider(value: value, in: range, step: 1)
            Text("\(Int(value.wrappedValue))")
                .monospacedDigit()
                .frame(width: 28, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func colorField(label: String,
                            color: Binding<Color>,
                            hex: Binding<String>,
                            focusTag: Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ColorPicker("", selection: color, supportsOpacity: false)
                    .labelsHidden()
                    .onChange(of: color.wrappedValue) {
                        hex.wrappedValue = $0.toHex() ?? hex.wrappedValue
                    }
                TextField("#rrggbb", text: hex)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 76)
                    .focused($focus, equals: focusTag)
                    .onSubmit { applyHex(hex.wrappedValue, to: color) }
            }
        }
    }

    private func applyHex(_ hex: String, to color: Binding<Color>) {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#").union(.whitespaces))
        guard clean.count == 6,
              clean.allSatisfy({ $0.isHexDigit })
        else { return }
        color.wrappedValue = Color(hex: clean)
    }

    private func fieldBorder(_ active: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .strokeBorder(active ? Color.accentColor : Color(nsColor: .separatorColor),
                          lineWidth: active ? 2 : 1)
    }
}
