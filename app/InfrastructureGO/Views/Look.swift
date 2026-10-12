import SwiftUI
import UIKit

/// How the game looks, in one place: a field journal of the watershed. Warm paper, deep creek blue, moss, copper,
/// the green of old copper and a little marigold. Titles are set in a serif face, everything to read in the plain one.
enum Look {
    static let paper = Color(red: 0.953, green: 0.918, blue: 0.847)
    static let paperDeep = Color(red: 0.905, green: 0.858, blue: 0.760)
    static let ink = Color(red: 0.13, green: 0.16, blue: 0.19)
    static let inkSoft = Color(red: 0.13, green: 0.16, blue: 0.19).opacity(0.62)
    static let creek = Color(red: 0.12, green: 0.31, blue: 0.42)
    static let moss = Color(red: 0.36, green: 0.52, blue: 0.22)
    static let copper = Color(red: 0.70, green: 0.42, blue: 0.20)
    static let verdigris = Color(red: 0.27, green: 0.58, blue: 0.52)
    static let marigold = Color(red: 0.95, green: 0.65, blue: 0.10)

    static func title(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .serif)
    }

    /// The colour that stands for how rare a keeper is. It is never the only cue, the word is always there too.
    static func colour(ofKind kind: String) -> Color {
        switch kind {
        case "uncommon": creek
        case "rare": marigold
        case "visitor": verdigris
        default: moss
        }
    }

    static func word(forKind kind: String) -> String {
        switch kind {
        case "uncommon": "Uncommon"
        case "rare": "Rare"
        case "visitor": "Visitor"
        default: "Common"
        }
    }

    /// A keeper's picture, rendered from the same model the meeting shows. The second pose is the one a mastered
    /// catch earns.
    static func picture(of keeper: String, pose: Bool = false) -> UIImage? {
        UIImage(named: "\(keeper)_\(pose ? "pose" : "portrait")")
    }

    /// The sign of a piece of gear.
    static func sign(ofGear piece: String) -> String {
        switch piece {
        case "boots": "shoe.fill"
        case "long_coil": "dot.radiowaves.left.and.right"
        case "lamp": "flashlight.on.fill"
        case "wide_marker": "mappin.and.ellipse"
        case "vest": "tshirt.fill"
        case "tuned_coil": "dial.medium.fill"
        case "field_tablet": "list.clipboard.fill"
        case "survey_wheel": "circle.dotted.circle"
        default: "shield.lefthalf.filled"
        }
    }
}

extension View {
    /// A sheet of the journal's paper with a soft edge.
    func paperCard(padding: CGFloat = 14) -> some View {
        self.padding(padding)
            .background(Look.paper, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Look.ink.opacity(0.10), lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
    }
}

/// A keeper's face on a paper disc: its picture once met, its shadow before.
struct KeeperFace: View {
    let keeper: String?
    let met: Bool
    var size: CGFloat = 44
    var ring: Color = Look.ink.opacity(0.18)

    var body: some View {
        ZStack {
            Circle().fill(Look.paper)
            if let keeper, let picture = Look.picture(of: keeper) {
                if met {
                    Image(uiImage: picture).resizable().scaledToFit().padding(size * 0.06)
                } else {
                    Image(uiImage: picture).renderingMode(.template).resizable().scaledToFit().padding(size * 0.06).foregroundStyle(Look.ink.opacity(0.55))
                }
            } else {
                Text("?").font(Look.title(size * 0.5)).foregroundStyle(Look.inkSoft)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(ring, lineWidth: max(1.5, size * 0.05)))
    }
}

/// A hard hat, drawn, because the worker's own picture is not made yet.
struct HardHat: Shape {
    func path(in box: CGRect) -> Path {
        var path = Path()
        let w = box.width, h = box.height
        path.move(to: CGPoint(x: box.minX + w * 0.14, y: box.minY + h * 0.66))
        path.addCurve(to: CGPoint(x: box.minX + w * 0.86, y: box.minY + h * 0.66),
                      control1: CGPoint(x: box.minX + w * 0.14, y: box.minY + h * 0.02), control2: CGPoint(x: box.minX + w * 0.86, y: box.minY + h * 0.02))
        path.closeSubpath()
        path.addRoundedRect(in: CGRect(x: box.minX + w * 0.02, y: box.minY + h * 0.64, width: w * 0.96, height: h * 0.16), cornerSize: CGSize(width: h * 0.08, height: h * 0.08))
        path.addRoundedRect(in: CGRect(x: box.minX + w * 0.44, y: box.minY + h * 0.14, width: w * 0.12, height: h * 0.5), cornerSize: CGSize(width: w * 0.05, height: w * 0.05))
        return path
    }
}

/// The apprentice as a small badge: a face under a hard hat, in the colours of the chosen figure, with the vest
/// once it is earned.
struct WorkerBadge: View {
    let figure: String?
    var vest = false
    var size: CGFloat = 44

    private var skin: Color { figure == "b" ? Color(red: 0.55, green: 0.38, blue: 0.27) : Color(red: 0.93, green: 0.76, blue: 0.62) }
    private var hat: Color { figure == "b" ? Look.verdigris : Look.marigold }

    var body: some View {
        ZStack {
            Circle().fill(Look.paperDeep)
            Capsule().fill(vest ? Look.marigold : Look.creek).frame(width: size * 0.7, height: size * 0.5).offset(y: size * 0.42)
            Circle().fill(skin).frame(width: size * 0.46, height: size * 0.46).offset(y: size * 0.06)
            HStack(spacing: size * 0.12) {
                Circle().fill(Look.ink).frame(width: size * 0.055, height: size * 0.055)
                Circle().fill(Look.ink).frame(width: size * 0.055, height: size * 0.055)
            }
            .offset(y: size * 0.07)
            HardHat().fill(hat).frame(width: size * 0.62, height: size * 0.4).offset(y: -size * 0.17)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Look.ink.opacity(0.2), lineWidth: 1.5))
        .accessibilityLabel("Your apprentice")
    }
}

/// A piece of gear as a round sign, grey until it is finished.
struct GearSign: View {
    let piece: String
    let owned: Bool
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle().fill(owned ? Look.creek : Look.paperDeep)
            if piece == "hard_hat" {
                HardHat().fill(owned ? Look.marigold : Look.inkSoft).frame(width: size * 0.56, height: size * 0.38)
            } else {
                Image(systemName: Look.sign(ofGear: piece)).font(.system(size: size * 0.44, weight: .semibold)).foregroundStyle(owned ? Look.paper : Look.inkSoft)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(Look.ink.opacity(0.15), lineWidth: 1))
    }
}

/// A small label that says how rare a keeper is, in a word and a colour.
struct KindBadge: View {
    let kind: String

    var body: some View {
        Text(Look.word(forKind: kind))
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Look.colour(ofKind: kind), in: Capsule())
            .foregroundStyle(kind == "rare" ? Look.ink : Look.paper)
    }
}

/// The bar that shows how far the player is from the next level.
struct LevelBar: View {
    let standing: Standing
    var quiet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(standing.rank), level \(standing.level)").font(quiet ? .subheadline.weight(.semibold) : .headline)
                Spacer()
                Text(standing.pointsToNext.map { "\($0) points to the next level" } ?? "The last level").font(.footnote).foregroundStyle(Look.inkSoft)
            }
            ProgressView(value: standing.fraction).tint(Look.creek)
        }
        .foregroundStyle(Look.ink)
    }
}

/// How many parts a piece of gear has, as a row of small squares.
struct PartsBar: View {
    let have: Int
    let of: Int
    var fresh = 0

    var body: some View {
        GeometryReader { box in
            let gap: CGFloat = of > 24 ? 1 : 2
            let width = max(1, (box.size.width - gap * CGFloat(max(0, of - 1))) / CGFloat(max(1, of)))
            HStack(spacing: gap) {
                ForEach(0..<max(1, of), id: \.self) { k in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(k < have - fresh ? Look.creek : k < have ? Look.marigold : Look.ink.opacity(0.14))
                        .frame(width: width)
                }
            }
        }
        .frame(height: 8)
        .accessibilityLabel("\(have) of \(of) parts")
    }
}
