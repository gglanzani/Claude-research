import SwiftUI

struct ContentView: View {
    @StateObject private var state = CardState()
    @State private var selectedTab: Int = 0
    @State private var zoom: CGFloat = 1.0
    @State private var zoomBase: CGFloat = 1.0
    @FocusState private var quoteFocused: Bool
    @FocusState private var authorFocused: Bool

    var body: some View {
        HSplitView {
            // Left panel — controls
            controlPanel
                .frame(minWidth: 300, maxWidth: 380)

            // Right panel — preview + export
            previewPanel
                .frame(minWidth: 500)
        }
        .focusedObject(state)
        .onAppear { quoteFocused = true }
    }

    // MARK: - Control Panel

    private var controlPanel: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Quote input
                quoteInputSection

                // Tabs for panels
                Picker("Panel", selection: $selectedTab) {
                    Text("Palette").tag(0)
                    Text("Type").tag(1)
                    Text("Layout").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                Group {
                    if selectedTab == 0 {
                        PalettePickerView(state: state)
                    } else if selectedTab == 1 {
                        TypographyPanelView(state: state)
                    } else {
                        LayoutPanelView(state: state)
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: selectedTab)
                .padding(.horizontal)
            }
            .padding(.vertical, 16)
        }
        .background(.windowBackground)
    }

    // MARK: - Quote Input

    private var quoteInputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Quote", systemImage: "quote.bubble")
                .font(.headline)

            TextEditor(text: $state.quote)
                .focused($quoteFocused)
                .font(.body)
                .frame(minHeight: 100, maxHeight: 180)
                .padding(8)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(quoteFocused ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.separator), lineWidth: 1)
                )

            Label("Author", systemImage: "person")
                .font(.headline)

            TextField("Author name", text: $state.author)
                .focused($authorFocused)
                .textFieldStyle(.plain)
                .font(.body)
                .padding(8)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(authorFocused ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.separator), lineWidth: 1)
                )
                .onSubmit { quoteFocused = true }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
    }

    // MARK: - Preview Panel

    private var previewPanel: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                Text("Preview")
                    .font(.headline)

                Spacer()

                // Zoom controls
                HStack(spacing: 4) {
                    Button { zoom = max(0.1, zoom / 1.25) } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .keyboardShortcut("-", modifiers: .command)

                    Text("\(Int(zoom * 100))%")
                        .font(.caption.monospacedDigit())
                        .frame(minWidth: 40)
                        .onTapGesture(count: 2) { zoom = 1.0 }

                    Button { zoom = min(10.0, zoom * 1.25) } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .keyboardShortcut("=", modifiers: .command)
                }

                Divider().frame(height: 16)

                Button {
                    Task { @MainActor in
                        ExportManager.copyToClipboard(state: state)
                    }
                } label: {
                    Label("Copy Image", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .help("Copy image to clipboard (⇧⌘C)")

                ExportButton(state: state)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)

            Divider()

            // Preview canvas
            GeometryReader { geo in
                let padding: CGFloat = 40
                let availableW = geo.size.width - padding * 2
                let availableH = geo.size.height - padding * 2
                let cardW = state.selectedSize.width
                let cardH = state.selectedSize.height
                let fitScale = min(availableW / cardW, availableH / cardH)
                let scale = fitScale * zoom

                ScrollView([.horizontal, .vertical]) {
                    CardPreviewView(state: state, previewScale: scale)
                        .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 8)
                        .padding(padding)
                        .frame(
                            minWidth: geo.size.width,
                            minHeight: geo.size.height
                        )
                }
            }
            .background(Color(NSColor.underPageBackgroundColor))
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        zoom = max(0.1, min(10.0, zoomBase * value))
                    }
                    .onEnded { value in
                        zoom = max(0.1, min(10.0, zoomBase * value))
                        zoomBase = zoom
                    }
            )
        }
    }
}

// MARK: - Export Button

struct ExportButton: View {
    @ObservedObject var state: CardState
    @State private var showMenu = false

    var body: some View {
        Menu {
            ForEach(ExportFormat.allCases) { format in
                Button {
                    Task { @MainActor in
                        ExportManager.export(state: state, format: format)
                    }
                } label: {
                    Label("Export as \(format.rawValue)", systemImage: exportIcon(format))
                }
            }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .menuStyle(.borderedButton)
        .keyboardShortcut("e", modifiers: .command)
    }

    private func exportIcon(_ format: ExportFormat) -> String {
        switch format {
        case .png: return "photo"
        case .webp: return "photo.artframe"
        case .svg: return "doc.text"
        }
    }
}

// MARK: - App Commands

struct AppCommands: Commands {
    @FocusedObject private var state: CardState?

    var body: some Commands {
        CommandMenu("Card") {
            Button("Copy Image") {
                if let state {
                    Task { @MainActor in
                        ExportManager.copyToClipboard(state: state)
                    }
                }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(state == nil)

            Button("Export…") {
                // handled by ExportButton
            }
            .keyboardShortcut("e", modifiers: .command)

            Divider()

            Button("Focus Quote") {}
                .keyboardShortcut("1", modifiers: .command)

            Button("Focus Author") {}
                .keyboardShortcut("2", modifiers: .command)
        }
    }
}
