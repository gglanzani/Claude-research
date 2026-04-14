import SwiftUI
import UniformTypeIdentifiers

struct CardPreviewPane: View {
    @EnvironmentObject var model: CardModel

    var body: some View {
        VStack(spacing: 0) {
            // Live preview
            GeometryReader { geo in
                let previewSize = fitSize(containerSize: geo.size,
                                         aspectRatio: model.aspectRatio.aspectRatio,
                                         padding: 48)
                CardView(model: model)
                    .frame(width: previewSize.width, height: previewSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.25), radius: 24, x: 0, y: 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            // Export toolbar
            HStack(spacing: 12) {
                Text("Export")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                exportButton("PNG",  icon: "photo",              format: .png)
                exportButton("WebP", icon: "photo.badge.checkmark", format: .webp)
                exportButton("SVG",  icon: "doc.richtext",        format: .svg)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        // Listen for menu-bar export commands
        .onReceive(NotificationCenter.default.publisher(for: .exportPNG))  { _ in runExport(.png)  }
        .onReceive(NotificationCenter.default.publisher(for: .exportWebP)) { _ in runExport(.webp) }
        .onReceive(NotificationCenter.default.publisher(for: .exportSVG))  { _ in runExport(.svg)  }
    }

    // MARK: - Export button

    @ViewBuilder
    private func exportButton(_ label: String, icon: String, format: ExportFormat) -> some View {
        Button {
            runExport(format)
        } label: {
            Label(label, systemImage: icon)
        }
        .buttonStyle(.bordered)
        .help("Export as \(label)")
    }

    // MARK: - Export logic

    @MainActor
    private func runExport(_ format: ExportFormat) {
        let outputSize = model.aspectRatio.outputSize

        let panel = NSSavePanel()
        panel.allowedContentTypes  = [format.utType]
        panel.nameFieldStringValue = "quote-card.\(format.fileExtension)"
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    let data = try ExportManager.export(model: model,
                                                        size: outputSize,
                                                        format: format)
                    try data.write(to: url, options: .atomic)
                } catch {
                    let alert = NSAlert(error: error)
                    alert.runModal()
                }
            }
        }
    }

    // MARK: - Layout helpers

    /// Scales the card to fit inside `containerSize` while maintaining `aspectRatio`.
    private func fitSize(containerSize: CGSize, aspectRatio: CGFloat, padding: CGFloat) -> CGSize {
        let w = containerSize.width  - padding
        let h = containerSize.height - padding
        guard w > 0, h > 0 else { return .zero }

        if w / aspectRatio <= h {
            return CGSize(width: w, height: w / aspectRatio)
        } else {
            return CGSize(width: h * aspectRatio, height: h)
        }
    }
}
