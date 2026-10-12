import SwiftUI

/// The few settings of the game and the credits of what it is made from.
struct SettingsSheet: View {
    @Environment(GameModel.self) private var game

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings").font(Look.title(24)).foregroundStyle(Look.ink)
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Easy catch", isOn: Binding(get: { game.progress.easyCatch }, set: { game.set(easyCatch: $0) }))
                    Text("Every aimed throw lands. For anyone who cannot or does not want to time a swipe.").font(.footnote).foregroundStyle(Look.inkSoft)
                }
                Toggle("Sound", isOn: Binding(get: { game.progress.sound }, set: { game.set(sound: $0) }))
                Toggle("Ticks in the hand", isOn: Binding(get: { game.progress.ticks }, set: { game.set(ticks: $0) }))
                VStack(alignment: .leading, spacing: 6) {
                    Text("What stays on this phone").font(.headline)
                    Text("Where you walked, what you found and what you earned are kept on this phone and nowhere else. Nothing is sent anywhere yet.")
                        .font(.footnote).foregroundStyle(Look.inkSoft)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Made from").font(.headline)
                    Text("The drains are those of the town's own map. \(game.content?.inlets.source ?? ""), \(game.content?.inlets.retrieved ?? "").").font(.footnote)
                    Text("The keepers are models of the pack Ultimate Monsters by Quaternius, public domain (CC0), repainted for this game.").font(.footnote)
                    Text("The sounds are from the Interface Sounds and Impact Sounds by Kenney and the Swishes Sound Pack by artisticdude, all public domain (CC0).").font(.footnote)
                }
                .foregroundStyle(Look.inkSoft)
            }
            .foregroundStyle(Look.ink)
            .tint(Look.creek)
            .padding(20)
        }
        .background(Look.paper)
        .preferredColorScheme(.light)
    }
}
