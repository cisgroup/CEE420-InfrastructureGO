import SwiftUI

/// What a meeting came to. The keeper leads, with one sentence about what changed. Then what the crate gave, and
/// only then, quietly, the points. Nothing here says more than what happened on this phone.
struct ResultCard: View {
    @Environment(GameModel.self) private var game
    let result: MeetingResult
    let done: () -> Void
    @State private var landed = false
    @State private var stamped = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                page
                if !result.filled.isEmpty || result.thanks > 0 { crate }
                if !result.jobsDone.isEmpty {
                    ForEach(result.jobsDone) { job in
                        Label("Job done: \(job.text)", systemImage: "checkmark.seal.fill").font(.subheadline).foregroundStyle(Look.moss)
                    }
                }
                quiet
                Button(action: done) {
                    Text("Done").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(Look.creek)
            }
            .padding(20)
        }
        .background(Look.paper)
        .preferredColorScheme(.light)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.62).delay(0.15)) { landed = true }
            if result.meeting.outcome == .mastered {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.5)) { stamped = true }
                    game.sound.play("seal")
                    game.haptics.thud()
                }
            }
            game.sound.play(result.finished.isEmpty ? "page" : "piece", volume: 0.7)
        }
    }

    /// The journal page the keeper lands on.
    private var page: some View {
        let won = result.meeting.outcome == .caught || result.meeting.outcome == .mastered
        return VStack(alignment: .leading, spacing: 10) {
            if let keeper = result.keeper {
                HStack(alignment: .center, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16).fill(Look.paperDeep.opacity(0.7))
                        if let picture = Look.picture(of: keeper.id, pose: result.meeting.outcome == .mastered) {
                            if won {
                                Image(uiImage: picture).resizable().scaledToFit().padding(4)
                            } else {
                                Image(uiImage: picture).renderingMode(.template).resizable().scaledToFit().padding(4).foregroundStyle(Look.ink.opacity(0.45))
                            }
                        }
                        if result.meeting.outcome == .mastered {
                            Image(systemName: "seal.fill").font(.system(size: 44)).foregroundStyle(Look.marigold)
                                .overlay(Image(systemName: "checkmark").font(.system(size: 17, weight: .black)).foregroundStyle(Look.ink))
                                .scaleEffect(stamped ? 1 : 2.4).opacity(stamped ? 1 : 0).rotationEffect(.degrees(stamped ? -12 : 10))
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(4)
                        }
                    }
                    .frame(width: 150, height: 150)
                    .scaleEffect(landed ? 1 : 0.4).rotationEffect(.degrees(landed ? -2 : -14)).opacity(landed ? 1 : 0)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(won || game.progress.met.contains(keeper.id) ? keeper.name : "???").font(Look.title(28)).foregroundStyle(Look.ink)
                        if won { Text(keeper.keeps).font(.subheadline.weight(.semibold)).foregroundStyle(Look.copper) }
                        KindBadge(kind: keeper.kind)
                    }
                }
            } else {
                Text("A look at the drain").font(Look.title(26)).foregroundStyle(Look.ink)
            }
            Text(result.line).font(.title3.weight(.semibold)).foregroundStyle(Look.ink)
            if let page = result.page, won, let at = page.nextAt {
                ProgressView(value: Double(page.meetings), total: Double(at)).tint(Look.moss)
            }
            if result.meeting.outcome == .mastered, let keeper = result.keeper {
                Text("\(keeper.pose). You read its \(keeper.tellWord).").font(.subheadline).foregroundStyle(Look.inkSoft)
            }
        }
    }

    private var crate: some View {
        VStack(alignment: .leading, spacing: 10) {
            let parts = result.crateParts + result.jobParts + result.levelParts
            Text(result.crateParts > 0 ? "From the crate" : "Handed over").font(.headline).foregroundStyle(Look.ink)
            Text(source(parts)).font(.footnote).foregroundStyle(Look.inkSoft)
            ForEach(result.filled) { filled in
                HStack(spacing: 12) {
                    GearSign(piece: filled.piece.id, owned: filled.after >= filled.piece.parts, size: 42)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(filled.piece.name).font(.subheadline.weight(.semibold)).foregroundStyle(Look.ink)
                            Spacer()
                            Text(filled.finished ? "Finished" : "\(filled.after) of \(filled.piece.parts)").font(.caption.weight(.semibold)).foregroundStyle(filled.finished ? Look.moss : Look.inkSoft)
                        }
                        PartsBar(have: filled.after, of: filled.piece.parts, fresh: filled.after - filled.before)
                        if filled.finished { Text(filled.piece.says).font(.footnote).foregroundStyle(Look.ink) }
                    }
                }
                .padding(10)
                .background(filled.finished ? Look.marigold.opacity(0.2) : Look.paperDeep.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
            }
            if result.thanks > 0 {
                Text("Your gear is complete. The crew says thank you with \(result.thanks) points.").font(.footnote).foregroundStyle(Look.inkSoft)
            }
        }
    }

    private func source(_ parts: Int) -> String {
        var from: [String] = []
        if result.crateParts > 0 { from.append("\(Words.count(result.crateParts, "part", "parts")) from the crate") }
        if result.jobParts > 0 { from.append("\(Words.count(result.jobParts, "part", "parts")) for a finished job") }
        if result.levelParts > 0 { from.append("\(Words.count(result.levelParts, "part", "parts")) for the new level") }
        return from.joined(separator: ", ") + "."
    }

    /// The quiet end of the card: the points, the level and where the look is kept.
    private var quiet: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(result.look).font(.footnote).foregroundStyle(Look.inkSoft)
            let extra = result.meeting.points - (game.content.map { SpawnRules.points(tier: result.need, greatCatch: false, rules: $0.rules) } ?? 0)
            if extra > 0 {
                Text("\(extra) more for \(result.meeting.outcome == .mastered ? (result.pageBefore?.meetings == 0 ? "a new keeper and the seal" : "the seal") : "a keeper new to you").")
                    .font(.footnote).foregroundStyle(Look.inkSoft)
            }
            LevelBar(standing: result.after, quiet: true)
            if result.after.level > result.before.level {
                Label("Level \(result.after.level). \(result.after.rank).", systemImage: "arrow.up.circle.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Look.creek)
            }
            Text("Saved on this phone. Desk play records no observation of a real drain.").font(.caption).foregroundStyle(Look.inkSoft)
        }
        .padding(12)
        .background(Look.paperDeep.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}
