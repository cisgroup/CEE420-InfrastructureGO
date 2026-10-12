import SwiftUI

/// The two halves of the game, the map where keepers are found and the journal where they are kept.
struct RootView: View {
    @Environment(GameModel.self) private var game
    @State private var tab = "map"

    var body: some View {
        #if DEBUG
        if let spike = game.opening.spike {
            SpikeView(name: spike, freeze: game.opening.freeze)
        } else {
            play
        }
        #else
        play
        #endif
    }

    @ViewBuilder
    private var play: some View {
        if let problem = game.problem {
            ContentUnavailableView("The game cannot start", systemImage: "exclamationmark.triangle", description: Text(problem))
        } else if game.progress.figure == nil {
            Onboarding()
        } else {
            TabView(selection: $tab) {
                Tab("Map", systemImage: "map.fill", value: "map") {
                    MapScreen()
                }
                Tab("Journal", systemImage: "book.fill", value: "journal") {
                    FieldGuideView()
                }
            }
            .tint(Look.creek)
            .preferredColorScheme(.light)
            .onAppear {
                game.location.start()
                game.moved()
                game.refreshJobs()
                game.startTicking()
                if let asked = game.opening.tab { tab = asked == "guide" ? "journal" : asked }
            }
            .onChange(of: game.location.fix) { _, _ in game.moved() }
            .onChange(of: tab) { _, _ in game.sound.play("page", volume: 0.35) }
        }
    }
}
