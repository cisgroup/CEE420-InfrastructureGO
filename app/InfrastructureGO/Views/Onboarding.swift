import SwiftUI

/// The first screen of a new player. One card says what the game is, the player picks a figure, and the map opens.
/// The game teaches the rest at the first drain.
struct Onboarding: View {
    @Environment(GameModel.self) private var game
    @State private var figure = "a"

    var body: some View {
        ZStack {
            Look.paper.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 22) {
                Spacer(minLength: 0)
                Text("InfrastructureGO").font(.subheadline.weight(.semibold)).foregroundStyle(Look.copper)
                Text("The hidden watershed").font(Look.title(34)).foregroundStyle(Look.ink)
                Text("Under the streets of Princeton runs a hidden watershed. Its keepers show themselves to people who look.")
                    .font(.title3).foregroundStyle(Look.ink)
                Text("You are the new apprentice at Public Works. Walk, find the drains, meet their keepers. Every look at a drain also helps the town know its drains.")
                    .font(.body).foregroundStyle(Look.inkSoft)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Pick your apprentice").font(.headline).foregroundStyle(Look.ink)
                    HStack(spacing: 18) {
                        ForEach(["a", "b"], id: \.self) { choice in
                            Button {
                                figure = choice
                                game.sound.play("select", volume: 0.5)
                            } label: {
                                WorkerBadge(figure: choice, size: 84)
                                    .overlay(Circle().stroke(figure == choice ? Look.creek : .clear, lineWidth: 4).padding(-5))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(choice == "a" ? "The first apprentice" : "The second apprentice")
                        }
                    }
                }
                Spacer(minLength: 0)
                Button {
                    game.choose(figure: figure)
                } label: {
                    Text("Start").font(.title3.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .tint(Look.creek)
                Text("The keepers are made up. A keeper at a drain says nothing about the real drain.").font(.footnote).foregroundStyle(Look.inkSoft)
            }
            .padding(26)
        }
        .preferredColorScheme(.light)
    }
}
