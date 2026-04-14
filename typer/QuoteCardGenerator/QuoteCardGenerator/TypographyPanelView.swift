import SwiftUI
import AppKit

struct TypographyPanelView: View {
    @ObservedObject var state: CardState
    @State private var availableFonts: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Typography", systemImage: "textformat")
                .font(.headline)

            // Quote font
            GroupBox("Quote") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        FontPickerButton(selectedFont: $state.quoteFontName, label: "Font")
                        Spacer()
                        Toggle("Italic", isOn: $state.italicizeQuote)
                            .toggleStyle(.checkbox)
                    }

                    LabeledSlider(label: "Size", value: $state.quoteFontSize, range: 20...120, format: "%.0f pt")
                }
                .padding(6)
            }

            // Author font
            GroupBox("Author") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        FontPickerButton(selectedFont: $state.authorFontName, label: "Font")
                        Spacer()
                        Toggle("Bold", isOn: $state.boldAuthor)
                            .toggleStyle(.checkbox)
                    }
                    LabeledSlider(label: "Size", value: $state.authorFontSize, range: 10...60, format: "%.0f pt")
                }
                .padding(6)
            }

            // Spacing
            GroupBox("Spacing") {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledSlider(label: "Line", value: $state.lineSpacing, range: 0...40, format: "%.0f")
                    LabeledSlider(label: "Author gap", value: $state.authorSpacing, range: 8...120, format: "%.0f")
                    LabeledSlider(label: "Tracking", value: $state.letterSpacing, range: -2...10, format: "%.1f")
                    LabeledSlider(label: "Padding", value: $state.padding, range: 20...200, format: "%.0f")
                }
                .padding(6)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Font Picker Button

struct FontPickerButton: View {
    @Binding var selectedFont: String
    let label: String
    @State private var showPicker = false

    var body: some View {
        Button(action: { showPicker = true }) {
            HStack(spacing: 6) {
                Text(selectedFont)
                    .font(.custom(selectedFont, size: 13))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.background, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPicker) {
            FontSearchPickerView(selectedFont: $selectedFont, isPresented: $showPicker)
        }
    }
}

// MARK: - Font Search Picker

struct FontSearchPickerView: View {
    @Binding var selectedFont: String
    @Binding var isPresented: Bool
    @State private var search: String = ""
    @State private var fonts: [String] = []
    @FocusState private var searchFocused: Bool

    var filtered: [String] {
        if search.isEmpty { return fonts }
        return fonts.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search fonts…", text: $search)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(.regularMaterial)

            Divider()

            ScrollViewReader { proxy in
                List(filtered, id: \.self, selection: Binding(
                    get: { selectedFont },
                    set: { if let v = $0 { selectedFont = v } }
                )) { font in
                    Text(font)
                        .font(.custom(font, size: 15))
                        .id(font)
                        .tag(font)
                }
                .listStyle(.inset)
                .onChange(of: filtered) { _ in
                    if let first = filtered.first {
                        proxy.scrollTo(first, anchor: .top)
                    }
                }
                .onAppear {
                    proxy.scrollTo(selectedFont, anchor: .center)
                }
            }

            Divider()

            HStack {
                Text(selectedFont)
                    .font(.custom(selectedFont, size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.escape)
                Button("Select") { isPresented = false }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
        .frame(width: 320, height: 480)
        .onAppear {
            fonts = loadFonts()
            searchFocused = true
        }
    }

    private func loadFonts() -> [String] {
        NSFontManager.shared.availableFontFamilies.sorted()
    }
}

// MARK: - Labeled Slider

struct LabeledSlider: View {
    let label: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let format: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Slider(value: $value, in: range)
            Text(String(format: format, value))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }
}
