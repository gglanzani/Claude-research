import SwiftUI

struct LayoutPanelView: View {
    @ObservedObject var state: CardState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Layout", systemImage: "rectangle.3.group")
                .font(.headline)

            // Card size
            GroupBox("Card Size") {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("", selection: $state.selectedSize) {
                        ForEach(CardSize.presets) { size in
                            Text("\(size.name) — \(size.aspectLabel)")
                                .tag(size)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)

                    Text("\(Int(state.selectedSize.width)) × \(Int(state.selectedSize.height)) px")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(6)
            }

            // Text alignment
            GroupBox("Text Alignment") {
                Picker("", selection: $state.textAlignment) {
                    ForEach(CardTextAlignment.allCases) { alignment in
                        Label(alignment.rawValue, systemImage: alignmentIcon(alignment))
                            .tag(alignment)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(6)
            }

            // Decoration
            GroupBox("Quote Style") {
                Picker("", selection: $state.quoteDecoration) {
                    ForEach(QuoteDecoration.allCases) { decoration in
                        Text(decoration.rawValue).tag(decoration)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .padding(6)
            }

            // Toggles
            GroupBox("Options") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Show author", isOn: $state.showAuthorLine)
                        .toggleStyle(.checkbox)
                }
                .padding(6)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func alignmentIcon(_ alignment: CardTextAlignment) -> String {
        switch alignment {
        case .leading: return "text.alignleft"
        case .center: return "text.aligncenter"
        case .trailing: return "text.alignright"
        }
    }
}
