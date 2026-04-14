import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: CardModel

    var body: some View {
        HSplitView {
            ControlsView()
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 400)

            CardPreviewPane()
                .frame(minWidth: 400, maxWidth: .infinity)
        }
        .frame(minWidth: 760, minHeight: 560)
    }
}
