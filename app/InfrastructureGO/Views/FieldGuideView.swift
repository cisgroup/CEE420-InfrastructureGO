import SwiftUI

/// The player's side of the story. The apprentice with the level and the gear, and every creature met so far.
struct FieldGuideView: View {
    @Environment(GameModel.self) private var game

    var body: some View {
        NavigationStack {
            ScrollView {
                if let content = game.content, let standing = game.standing {
                    VStack(alignment: .leading, spacing: 22) {
                        apprentice(content, standing)
                        creatures(content)
                        gear(content)
                        Text("The other players' reports on the map are made up for now, so that every kind of drain can be tried. They become real when the game's server exists.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(18)
                }
            }
            .navigationTitle("Field Guide")
        }
    }

    private func apprentice(_ content: GameContent, _ standing: Standing) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("⛑️").font(.system(size: 44))
                VStack(alignment: .leading, spacing: 2) {
                    Text(content.gear.role.name).font(.headline)
                    Text("\(game.progress.points) points from \(Words.count(game.progress.catches.count, "catch", "catches")) at \(Words.count(Set(game.progress.catches.map(\.site)).count, "drain", "drains"))")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            LevelBar(standing: standing)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func creatures(_ content: GameContent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Creatures").font(.title3.weight(.bold))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(content.species) { species in
                    let count = game.progress.count(of: species.id)
                    VStack(spacing: 6) {
                        Text(count > 0 ? Look.picture(of: species.id) : "?").font(.system(size: 40, weight: .heavy, design: .rounded))
                            .foregroundStyle(Look.colour(of: Tier(rawValue: species.tier) ?? .common).opacity(count > 0 ? 1 : 0.55))
                        Text(count > 0 ? species.name : "Not met yet").font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
                        Text(count > 0 ? "Caught \(Words.count(count, "time", "times"))" : (species.pool == "storm" ? "Comes with a storm" : "\(Words.name(of: Tier(rawValue: species.tier) ?? .common)) drains"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 118)
                    .padding(8)
                    .background(Look.colour(of: Tier(rawValue: species.tier) ?? .common).opacity(count > 0 ? 0.16 : 0.06), in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    private func gear(_ content: GameContent) -> some View {
        let owned = Set(Progression.gear(at: game.progress.points, in: content.gear).map(\.id))
        return VStack(alignment: .leading, spacing: 10) {
            Text("Gear").font(.title3.weight(.bold))
            ForEach(content.gear.levels.filter { $0.gear != nil }, id: \.level) { level in
                if let piece = content.gear.gear.first(where: { $0.id == level.gear }) {
                    let has = owned.contains(piece.id)
                    HStack(alignment: .top, spacing: 12) {
                        Text(has ? Look.picture(ofGear: piece.id) : "🔒").font(.title).frame(width: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(piece.name).font(.subheadline.weight(.semibold))
                            if has, let fact = content.facts.fact(id: piece.factId) {
                                Text(fact.text).font(.footnote).foregroundStyle(.secondary)
                            } else if !has {
                                Text("Level \(level.level), at \(level.points) points.").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(.thinMaterial.opacity(has ? 1 : 0.5), in: RoundedRectangle(cornerRadius: 12))
                    .opacity(has ? 1 : 0.7)
                }
            }
        }
    }
}
