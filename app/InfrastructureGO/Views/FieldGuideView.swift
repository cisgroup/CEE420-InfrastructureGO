import SwiftUI

/// The journal, the player's side of the story: the apprentice with the gear, the keepers met so far and the ones
/// still missing, the jobs of the crew and the streets of the town.
struct FieldGuideView: View {
    @Environment(GameModel.self) private var game
    @State private var allStreets = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let content = game.content, let standing = game.standing {
                    VStack(alignment: .leading, spacing: 24) {
                        apprentice(content, standing)
                        keepers(content)
                        gear(content)
                        if game.showsJobs { jobs }
                        streets
                        Text("Where you walked and what you found is kept on this phone and nowhere else.").font(.footnote).foregroundStyle(Look.inkSoft)
                    }
                    .padding(18)
                }
            }
            .background(Look.paper)
            .navigationTitle("Journal")
            .navigationDestination(for: Keeper.self) { keeper in
                KeeperPage(keeper: keeper)
            }
        }
        .preferredColorScheme(.light)
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(Look.title(22)).foregroundStyle(Look.ink)
    }

    private func apprentice(_ content: GameContent, _ standing: Standing) -> some View {
        let found = game.found
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                WorkerBadge(figure: game.progress.figure, vest: game.opens("more_shadows"), size: 72)
                VStack(alignment: .leading, spacing: 3) {
                    Text(content.gear.role.name).font(.headline).foregroundStyle(Look.ink)
                    Text("\(Words.count(game.progress.looked.count, "drain", "drains")) looked at, \(Words.count(game.progress.met.count, "keeper", "keepers")) met")
                        .font(.subheadline).foregroundStyle(Look.inkSoft)
                    Text("\(found.known) of \(found.all) drains found").font(.subheadline).foregroundStyle(Look.inkSoft)
                }
            }
            LevelBar(standing: standing)
            Text("\(game.progress.points) points").font(.footnote).foregroundStyle(Look.inkSoft)
        }
        .padding(14)
        .background(Look.paperDeep.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
    }

    private func keepers(_ content: GameContent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            heading("Keepers")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach(content.keepers) { keeper in
                    let page = Journal.page(of: keeper.id, in: game.progress, rungs: content.world.rungs)
                    NavigationLink(value: keeper) {
                        VStack(spacing: 5) {
                            KeeperFace(keeper: keeper.id, met: page.meetings > 0, size: 78, ring: page.meetings > 0 ? Look.colour(ofKind: keeper.kind) : Look.ink.opacity(0.2))
                                .overlay(alignment: .bottomTrailing) {
                                    if page.seals > 0 {
                                        Image(systemName: "seal.fill").font(.system(size: 22)).foregroundStyle(Look.marigold).overlay(Image(systemName: "checkmark").font(.system(size: 9, weight: .black)).foregroundStyle(Look.ink))
                                    }
                                }
                            Text(page.meetings > 0 ? keeper.name : "Not met yet").font(.subheadline.weight(.semibold)).foregroundStyle(Look.ink)
                            Text(page.meetings > 0 ? page.rung.name : keeper.hint).font(.caption).foregroundStyle(Look.inkSoft).multilineTextAlignment(.center).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func gear(_ content: GameContent) -> some View {
        let next = Gear.next(parts: game.progress.parts, pinned: game.progress.pinned, in: content.gear)
        return VStack(alignment: .leading, spacing: 10) {
            heading("Gear")
            Text("Crates, finished jobs and new levels hand you parts. They fill one piece at a time. Tap a piece to fill it first.")
                .font(.footnote).foregroundStyle(Look.inkSoft)
            ForEach(content.gear.pieces) { piece in
                let have = min(piece.parts, game.progress.parts[piece.id] ?? 0)
                let owned = have >= piece.parts
                Button {
                    if !owned {
                        game.pin(game.progress.pinned == piece.id ? nil : piece.id)
                        game.sound.play("select", volume: 0.4)
                    }
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        GearSign(piece: piece.id, owned: owned, size: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(piece.name).font(.subheadline.weight(.semibold)).foregroundStyle(Look.ink)
                                if next?.id == piece.id { Text("filling now").font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 2).background(Look.marigold, in: Capsule()).foregroundStyle(Look.ink) }
                                Spacer(minLength: 0)
                                if !owned { Text("\(have) of \(piece.parts)").font(.caption).foregroundStyle(Look.inkSoft) }
                            }
                            Text(piece.says).font(.footnote).foregroundStyle(Look.inkSoft).multilineTextAlignment(.leading)
                            if !owned { PartsBar(have: have, of: piece.parts) }
                        }
                    }
                    .padding(10)
                    .background(owned ? Look.creek.opacity(0.10) : Look.paperDeep.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(owned ? "\(piece.name), finished" : "\(piece.name), \(have) of \(piece.parts) parts")
            }
        }
    }

    private var jobs: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading("Jobs of the crew")
            if game.progress.jobs.isEmpty {
                Text("No job today.").font(.footnote).foregroundStyle(Look.inkSoft)
            }
            ForEach(Array(game.progress.jobs.enumerated()), id: \.element.id) { index, job in
                HStack(spacing: 12) {
                    Image(systemName: job.isFinished ? "checkmark.seal.fill" : "circle.dashed").font(.title2).foregroundStyle(job.isFinished ? Look.moss : Look.inkSoft)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(job.text).font(.subheadline.weight(.semibold)).foregroundStyle(Look.ink)
                        if job.isFinished {
                            Text("Done. It paid a part of gear.").font(.caption).foregroundStyle(Look.inkSoft)
                        } else if job.count > 1 {
                            ProgressView(value: Double(job.done), total: Double(job.count)).tint(Look.creek)
                            Text("\(job.done) of \(job.count)").font(.caption).foregroundStyle(Look.inkSoft)
                        }
                    }
                    Spacer(minLength: 0)
                    if !job.isFinished && game.canSwapJob {
                        Button("Another") { game.swapJob(at: index) }.font(.caption).buttonStyle(.bordered).tint(Look.creek)
                    }
                }
                .padding(10)
                .background(Look.paperDeep.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
            }
            if let hunt = game.huntLine {
                Label(hunt, systemImage: "scope").font(.footnote).foregroundStyle(Look.ink).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Look.marigold.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var streets: some View {
        let all = game.streets
        let shown = allStreets ? all : Array(all.prefix(6))
        return VStack(alignment: .leading, spacing: 8) {
            heading("Streets")
            ForEach(shown, id: \.road) { street in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(street.road).font(.subheadline).foregroundStyle(Look.ink)
                        Spacer()
                        Text("\(street.looked) of \(street.all) drains").font(.caption).foregroundStyle(Look.inkSoft)
                    }
                    ProgressView(value: Double(street.looked), total: Double(max(1, street.all))).tint(street.looked == street.all ? Look.moss : Look.creek)
                }
            }
            if all.count > 6 {
                Button(allStreets ? "Fewer streets" : "All \(all.count) streets") { allStreets.toggle() }.font(.footnote).tint(Look.creek)
            }
        }
    }
}
