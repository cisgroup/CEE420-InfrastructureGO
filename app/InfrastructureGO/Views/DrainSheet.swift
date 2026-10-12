import SwiftUI

/// What the game knows about one drain, and the way to it.
struct DrainSheet: View {
    @Environment(GameModel.self) private var game
    @Environment(\.dismiss) private var dismiss
    let head: Inlet
    let onLook: () -> Void

    var body: some View {
        let fence = game.fence(of: head)
        let holds = game.holds(head)
        let near = (game.distance(to: head) ?? .infinity) <= (game.content?.world.senseM ?? 80)
        let who = holds && near ? game.keeper(at: head) : nil
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                if holds && near {
                    KeeperFace(keeper: who?.id, met: who.map { game.progress.met.contains($0.id) } ?? false, size: 56)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(head.road.isEmpty ? "A drain" : head.road).font(Look.title(24)).foregroundStyle(Look.ink)
                    Text(headline(holds: holds, near: near, who: who)).font(.subheadline).foregroundStyle(Look.inkSoft)
                }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 5) {
                Label(Words.lastLook(game.progress.lastLook(at: head.id), now: game.now), systemImage: "eye")
                if holds { Label(Words.crate(parts: game.crateParts(of: head)), systemImage: "shippingbox") }
                Label(Words.grates(game.grates(of: head)), systemImage: "square.grid.3x3")
                Label(Words.fence(fence), systemImage: "figure.walk")
            }
            .font(.subheadline)
            .foregroundStyle(Look.ink)
            if game.opens("town_card") {
                VStack(alignment: .leading, spacing: 3) {
                    Text("The town's card").font(.footnote.weight(.semibold))
                    Text("\(head.type.isEmpty ? "Type not on file" : head.type). \(head.grate.isEmpty ? "Grate not on file" : head.grate). \(owner)")
                        .font(.footnote)
                    Text("From the town's map of its drains, \(game.content?.inlets.retrieved ?? "").").font(.caption2)
                }
                .foregroundStyle(Look.inkSoft)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Look.paperDeep.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
            }
            Spacer(minLength: 0)
            if case .inside = fence, holds {
                Button(action: onLook) {
                    Text("Take a look").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(Look.creek)
            } else if holds {
                Button {
                    game.target = head
                    dismiss()
                } label: {
                    Text("Lead me there").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(Look.creek)
            }
            if holds {
                Button {
                    game.leave(head)
                    dismiss()
                } label: {
                    Text("Leave this one").font(.subheadline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Look.ink)
                Text("For a drain you cannot or should not walk to. Your walk goes on elsewhere.").font(.caption).foregroundStyle(Look.inkSoft)
            }
            #if DEBUG
            Button {
                game.stand(at: head)
                game.target = head
                dismiss()
            } label: {
                Text("At your desk: stand at this drain").font(.footnote).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            #endif
        }
        .padding(20)
        .background(Look.paper)
        .preferredColorScheme(.light)
    }

    private func headline(holds: Bool, near: Bool, who: Keeper?) -> String {
        if game.progress.left.contains(head.id) { return "You left this one alone." }
        if game.rests(head) { return "Resting. You looked here today." }
        guard near else { return "Too far to see who is there." }
        guard let who else { return "Nobody is out right now." }
        return game.progress.met.contains(who.id) ? "\(who.name), \(who.keeps)." : "Someone you have not met."
    }

    private var owner: String {
        switch head.owner {
        case "Municipality": "Owned by the town."
        case "County": "Owned by the county."
        case "State": "Owned by the State."
        case "Other Municipality": "Owned by a neighbouring town."
        case "Private": "Privately owned."
        default: "Owner not on file."
        }
    }
}
