import SwiftUI

/// The two halves of the game, the map where drains are found and the field guide where the catches are kept.
struct RootView: View {
    @Environment(GameModel.self) private var game
    @State private var tab = "map"

    var body: some View {
        #if DEBUG
        if let spike = game.opening.spike {
            SpikeView(name: spike, freeze: game.opening.freeze)
        } else {
            game_
        }
        #else
        game_
        #endif
    }

    @ViewBuilder
    private var game_: some View {
        if let problem = game.problem {
            ContentUnavailableView("The game cannot start", systemImage: "exclamationmark.triangle", description: Text(problem))
        } else {
            TabView(selection: $tab) {
                Tab("Map", systemImage: "map.fill", value: "map") {
                    MapScreen()
                }
                Tab("Field Guide", systemImage: "book.fill", value: "guide") {
                    FieldGuideView()
                }
            }
            .tint(Look.water)
            .onAppear {
                game.location.start()
                if let asked = game.opening.tab { tab = asked }
            }
        }
    }
}
