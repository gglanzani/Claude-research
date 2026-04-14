import SwiftUI

@main
struct QuoteCardApp: App {
    @StateObject private var model = CardModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 960, height: 680)
        .commands {
            // Replace default New with nothing (single-window app)
            CommandGroup(replacing: .newItem) { }

            CommandMenu("Card") {
                Button("Export as PNG…") {
                    NotificationCenter.default.post(name: .exportPNG, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command])

                Button("Export as WebP…") {
                    NotificationCenter.default.post(name: .exportWebP, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("Export as SVG…") {
                    NotificationCenter.default.post(name: .exportSVG, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .option])
            }
        }
    }
}

extension Notification.Name {
    static let exportPNG  = Notification.Name("QuoteCard.exportPNG")
    static let exportWebP = Notification.Name("QuoteCard.exportWebP")
    static let exportSVG  = Notification.Name("QuoteCard.exportSVG")
}
