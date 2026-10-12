#if DEBUG
import SwiftUI

/// The desk panel of debug builds, for trying the game without walking: jump to a zone, let a day or a week
/// pass, or start over. Nothing here exists in a build for players.
struct DeskPanel: View {
    @Environment(GameModel.self) private var game
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("At your desk").font(Look.title(22)).foregroundStyle(Look.ink)
            Text("Press and hold the map to walk there. It is \(game.today), week \(game.week.suffix(2)).").font(.footnote).foregroundStyle(Look.inkSoft)
            HStack {
                ForEach(game.content?.zones.zones ?? []) { zone in
                    Button("Jump to \(zone.name)") {
                        game.jump(to: zone.id)
                        dismiss()
                    }
                    .font(.footnote)
                }
            }
            .buttonStyle(.bordered)
            HStack {
                Button("Next day") { game.skip(days: 1) }
                Button("Next week") { game.skip(days: 7) }
            }
            .buttonStyle(.bordered)
            if let visit = game.visitorOfMyZone {
                Button("Walk to this week's visitor") {
                    game.walk(to: visit.site.coordinate, metresPerSecond: 40)
                    dismiss()
                }
                .buttonStyle(.bordered)
            } else {
                Text("A visitor comes to town once two pieces of gear are finished.").font(.footnote).foregroundStyle(Look.inkSoft)
            }
            Toggle("Easy catch", isOn: Binding(get: { game.progress.easyCatch }, set: { game.set(easyCatch: $0) }))
            Toggle("Sound", isOn: Binding(get: { game.progress.sound }, set: { game.set(sound: $0) }))
            Button("Start over", role: .destructive) {
                game.startOver()
                dismiss()
            }
            .buttonStyle(.bordered)
            Spacer(minLength: 0)
        }
        .tint(Look.creek)
        .padding(20)
        .background(Look.paper)
        .preferredColorScheme(.light)
    }
}
#endif
