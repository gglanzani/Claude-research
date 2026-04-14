import SwiftUI
import AppKit

/// A button that opens the system NSFontPanel and writes the chosen font back
/// through the provided binding.
struct FontPickerButton: NSViewRepresentable {
    @Binding var font: NSFont

    func makeCoordinator() -> Coordinator {
        Coordinator(font: $font)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title(for: font),
                              target: context.coordinator,
                              action: #selector(Coordinator.openFontPanel(_:)))
        button.bezelStyle      = .rounded
        button.imagePosition   = .imageLeading
        button.image           = NSImage(systemSymbolName: "textformat", accessibilityDescription: nil)
        button.imageScaling    = .scaleProportionallyDown
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        button.title                  = title(for: font)
        context.coordinator.lastFont  = font
    }

    private func title(for font: NSFont) -> String {
        let family = font.familyName ?? font.fontName
        return "\(family)  \(Int(font.pointSize)) pt"
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        @Binding var font: NSFont
        /// Tracks the current font so we can hand it to NSFontManager.convert.
        var lastFont: NSFont

        init(font: Binding<NSFont>) {
            _font    = font
            lastFont = font.wrappedValue
        }

        @objc func openFontPanel(_ sender: Any?) {
            let manager = NSFontManager.shared
            let panel   = NSFontPanel.shared
            panel.setPanelFont(lastFont, isMultiple: false)
            manager.target = self
            manager.action = #selector(changeFont(_:))
            panel.orderFront(sender)
        }

        /// Called by NSFontManager when the user changes the selection in the font panel.
        @objc func changeFont(_ sender: NSFontManager?) {
            guard let manager = sender else { return }
            let newFont = manager.convert(lastFont)
            font     = newFont
            lastFont = newFont
        }

        override func responds(to selector: Selector!) -> Bool {
            selector == #selector(changeFont(_:)) || super.responds(to: selector)
        }
    }
}
