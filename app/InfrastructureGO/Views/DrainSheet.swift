import SwiftUI

/// What the game knows about one drain, and the way to it.
struct DrainSheet: View {
    @Environment(GameModel.self) private var game
    @Environment(\.dismiss) private var dismiss
    let head: Inlet
    let onCatch: () -> Void
    let onShow: () -> Void

    var body: some View {
        let seen = game.outlook(of: head)
        let fence = game.fence(of: head)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(head.road.isEmpty ? "A drain" : head.road).font(.title2.weight(.bold))
                Spacer()
                if let seen { TierBadge(tier: seen.tier) }
            }
            if let seen {
                Text(seen.sentence).font(.body)
                Text(seen.tier == .resting ? "A report here is worth \(seen.points) points today." : "A catch here is worth \(seen.points) points, and 5 more for a great catch.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Label(Words.grates(game.grates(of: head)), systemImage: "square.grid.3x3")
                Label(owner, systemImage: "building.columns")
                Label(Words.fence(fence), systemImage: "figure.walk")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if case .inside = fence {
                Button(action: onCatch) {
                    Text(seen?.tier == .resting ? "Report again" : "Catch").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Look.water)
            } else {
                Button {
                    game.target = head
                    onShow()
                    dismiss()
                } label: {
                    Text("Guide me there").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Look.water)
            }
            #if DEBUG
            Button {
                game.stand(at: head)
                game.target = head
            } label: {
                Text("Stand at this drain, for trying the game without walking").font(.footnote).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            #endif
        }
        .padding(20)
    }

    private var owner: String {
        switch head.owner {
        case "Municipality": "Owned by the town."
        case "County": "Owned by the county."
        case "State": "Owned by the State."
        case "Other Municipality": "Owned by a neighbouring town."
        case "Private": "Privately owned."
        default: "Owner unknown."
        }
    }
}
