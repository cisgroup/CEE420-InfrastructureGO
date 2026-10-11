import SwiftUI

@main
struct InfrastructureGOApp: App {
    @State private var game = GameModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(game)
        }
    }
}
