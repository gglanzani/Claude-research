import SwiftUI

struct ContentView: View {
    @StateObject private var state = CardState()
    @State private var selectedTab: Int = 0
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
                        .strokeBorder(quoteFocused ? Color.accentColor : Color.separator, lineWidth: 1)
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
                        .strokeBorder(authorFocused ? Color.accentColor : Color.separator, lineWidth: 1)
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

                ExportButton(state: state)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)

            Divider()

            // Preview canvas
            ScrollView([.horizontal, .vertical]) {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        CardPreviewView(state: state)
                            .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 8)
                        Spacer()
                    }
                    Spacer()
                }
                .frame(minWidth: 500, minHeight: 500)
            }
            .background(Color(NSColor.underPageBackgroundColor))
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
    var body: some Commands {
        CommandMenu("Card") {
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
