import SwiftUI

/// A keeper's page in the journal. It grows with every meeting: met, known, friend and old friend, and apart from
/// those the seal of a mastered catch.
struct KeeperPage: View {
    @Environment(GameModel.self) private var game
    let keeper: Keeper

    var body: some View {
        let rungs = game.content?.world.rungs ?? [1, 3, 7, 15]
        let page = Journal.page(of: keeper.id, in: game.progress, rungs: rungs)
        let met = page.meetings > 0
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom, spacing: 12) {
                    picture(pose: false, met: met)
                    if page.seals > 0 { picture(pose: true, met: true) }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(met ? keeper.name : "Not met yet").font(Look.title(30)).foregroundStyle(Look.ink)
                    if met { Text(keeper.keeps.prefix(1).uppercased() + keeper.keeps.dropFirst()).font(.headline).foregroundStyle(Look.copper) }
                    KindBadge(kind: keeper.kind)
                }
                if met {
                    Text(keeper.joke).font(.body).foregroundStyle(Look.ink)
                } else {
                    Label(keeper.hint, systemImage: "questionmark.circle").font(.body).foregroundStyle(Look.ink)
                }
                ladder(page, rungs: rungs)
                if page.rung >= .known {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("What you know").font(.headline)
                        Text(keeper.tell).font(.body)
                    }
                    .foregroundStyle(Look.ink)
                }
                seal(page)
                if let first = page.firstAt, let site = page.firstSite, let head = game.content?.inlets[site] {
                    Text("First met \(first.formatted(date: .abbreviated, time: .omitted))\(head.road.isEmpty ? "" : " on \(head.road)").")
                        .font(.footnote).foregroundStyle(Look.inkSoft)
                }
                if page.rung >= .friend {
                    Button(game.progress.friend == keeper.id ? "Walking with you" : "Take along on the map") {
                        game.befriend(game.progress.friend == keeper.id ? nil : keeper.id)
                    }
                    .buttonStyle(.borderedProminent).tint(Look.creek)
                }
                Text("\(keeper.credit). A made up keeper, it says nothing about real drains or real animals.").font(.caption).foregroundStyle(Look.inkSoft)
            }
            .padding(20)
        }
        .background(Look.paper)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.light)
    }

    private func picture(pose: Bool, met: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18).fill(Look.paperDeep.opacity(0.6))
            if let picture = Look.picture(of: keeper.id, pose: pose) {
                if met {
                    Image(uiImage: picture).resizable().scaledToFit().padding(6)
                } else {
                    Image(uiImage: picture).renderingMode(.template).resizable().scaledToFit().padding(6).foregroundStyle(Look.ink.opacity(0.5))
                }
            }
            if pose {
                Text(keeper.pose).font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 3).background(Look.marigold, in: Capsule())
                    .foregroundStyle(Look.ink).frame(maxHeight: .infinity, alignment: .bottom).padding(8)
            }
        }
        .frame(height: 210)
        .frame(maxWidth: .infinity)
    }

    private func ladder(_ page: Page, rungs: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(page.meetings == 0 ? "Meetings" : Words.count(page.meetings, "meeting", "meetings")).font(.headline).foregroundStyle(Look.ink)
            HStack(spacing: 8) {
                ForEach(Array([Rung.met, .known, .friend, .oldFriend].enumerated()), id: \.offset) { index, rung in
                    let reached = page.rung >= rung
                    VStack(spacing: 4) {
                        Image(systemName: reached ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(reached ? Look.moss : Look.inkSoft)
                        Text(rung.name).font(.caption2.weight(.semibold)).foregroundStyle(Look.ink)
                        Text(rungs.indices.contains(index) ? "at \(rungs[index])" : "").font(.caption2).foregroundStyle(Look.inkSoft)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            if let at = page.nextAt, page.meetings > 0 {
                ProgressView(value: Double(page.meetings), total: Double(at)).tint(Look.creek)
            }
        }
        .padding(12)
        .background(Look.paperDeep.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
    }

    private func seal(_ page: Page) -> some View {
        HStack(spacing: 12) {
            Image(systemName: page.seals > 0 ? "seal.fill" : "seal").font(.system(size: 34)).foregroundStyle(page.seals > 0 ? Look.marigold : Look.inkSoft)
            VStack(alignment: .leading, spacing: 2) {
                Text(page.seals > 0 ? "\(keeper.pose), \(Words.count(page.seals, "time", "times"))" : "The seal").font(.subheadline.weight(.semibold))
                Text(page.seals > 0 ? "You read its \(keeper.tellWord) and it landed on your marker." : "Read its tell and throw to where it will land.").font(.footnote).foregroundStyle(Look.inkSoft)
            }
        }
        .foregroundStyle(Look.ink)
    }
}
