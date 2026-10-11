import SwiftUI

/// How the game looks, in one place. A tier has a colour and a sign, a species has a small picture for lists.
enum Look {
    static let ink = Color(red: 0.11, green: 0.15, blue: 0.20)
    static let water = Color(red: 0.04, green: 0.36, blue: 0.54)
    static let zone = Color(red: 0.91, green: 0.46, blue: 0.0)
    static let gold = Color(red: 0.98, green: 0.75, blue: 0.14)

    static func colour(of tier: Tier) -> Color {
        switch tier {
        case .resting: Color(red: 0.60, green: 0.64, blue: 0.68)
        case .common: Color(red: 0.22, green: 0.62, blue: 0.33)
        case .uncommon: Color(red: 0.05, green: 0.55, blue: 0.62)
        case .rare: Color(red: 0.48, green: 0.25, blue: 0.86)
        }
    }

    static func sign(of tier: Tier) -> String {
        switch tier {
        case .resting: "moon.zzz.fill"
        case .common: "pawprint.fill"
        case .uncommon: "pawprint.fill"
        case .rare: "sparkles"
        }
    }

    /// A small picture of a species for lists and cards, until every species has its own drawing.
    static func picture(of species: String?) -> String {
        switch species {
        case "water_strider": "🦟"
        case "green_frog": "🐸"
        case "crayfish": "🦞"
        case "painted_turtle": "🐢"
        case "spotted_salamander": "🦎"
        case "great_blue_heron": "🪶"
        case "storm_eel": "⚡️"
        case "leaf_sprite": "🍂"
        default: "💤"
        }
    }

    static func picture(ofGear gear: String) -> String {
        switch gear {
        case "hard_hat": "⛑️"
        case "vest": "🦺"
        case "boots": "🥾"
        case "rake": "🧹"
        case "flashlight": "🔦"
        case "field_tablet": "📱"
        case "survey_wheel": "🛞"
        case "key_ring": "🗝️"
        default: "🎒"
        }
    }
}

/// The marker of a drain on the map. Its colour and size say how badly the town needs a look there.
struct DrainMarker: View {
    let tier: Tier
    var isTarget = false

    var body: some View {
        let size: CGFloat = tier == .rare ? 34 : tier == .resting ? 22 : 28
        ZStack {
            if isTarget {
                Circle().stroke(Look.gold, lineWidth: 4).frame(width: size + 12, height: size + 12)
            }
            Circle()
                .fill(Look.colour(of: tier))
                .frame(width: size, height: size)
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            Image(systemName: Look.sign(of: tier))
                .font(.system(size: size * 0.46, weight: .bold))
                .foregroundStyle(.white)
        }
        .accessibilityLabel("\(Words.name(of: tier)) drain")
    }
}

/// A small label that names a tier.
struct TierBadge: View {
    let tier: Tier

    var body: some View {
        Label(Words.name(of: tier), systemImage: Look.sign(of: tier))
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Look.colour(of: tier), in: Capsule())
            .foregroundStyle(.white)
    }
}

/// The bar that shows how far the player is from the next level.
struct LevelBar: View {
    let standing: Standing

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Level \(standing.level)").font(.headline)
                Spacer()
                Text(standing.pointsToNext.map { "\($0) points to the next level" } ?? "The last level").font(.footnote).foregroundStyle(.secondary)
            }
            ProgressView(value: standing.fraction).tint(Look.water)
        }
    }
}
