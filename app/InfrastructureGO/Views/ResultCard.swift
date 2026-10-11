import SwiftUI

/// What a catch came to. The creature, the points with their reason, the level, and any gear the catch earned.
struct ResultCard: View {
    @Environment(GameModel.self) private var game
    let result: CatchResult
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(Look.picture(of: result.species?.id)).font(.system(size: 72))
                Text(result.species.map { "You caught a \($0.name)" } ?? "The drain rests").font(.title2.weight(.bold)).multilineTextAlignment(.center)
                TierBadge(tier: result.tier)
                Text(result.sentence).font(.body).multilineTextAlignment(.center)
                LevelBar(standing: result.after)
                ForEach(result.newGear) { gear in
                    VStack(alignment: .leading, spacing: 6) {
                        Label("New gear. \(gear.name)", systemImage: "gift.fill").font(.headline).foregroundStyle(Look.zone)
                        if let fact = game.content?.facts.fact(id: gear.factId) {
                            Text(fact.text).font(.subheadline)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Look.gold.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
                }
                Text("Saved on this phone. The report reaches the town's map once the game has its server.").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button(action: onDone) {
                    Text("Done").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Look.water)
            }
            .padding(22)
        }
    }
}
