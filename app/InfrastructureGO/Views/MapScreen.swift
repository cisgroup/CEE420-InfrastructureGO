import MapKit
import SwiftUI

/// The map of the game. Drains that can be caught carry a marker whose colour says how badly the town needs a look
/// there. Tapping a marker tells more, and standing at a drain opens the catch.
struct MapScreen: View {
    @Environment(GameModel.self) private var game
    @State private var camera: MapCameraPosition = .automatic
    @State private var pins: [DrainPin] = []
    @State private var tooFar = false
    @State private var selected: Inlet?
    @State private var encounter: Inlet?
    @State private var result: CatchResult?
    @State private var centred = false

    var body: some View {
        Map(position: $camera) {
            if let zones = game.content?.zones.zones {
                ForEach(zones) { zone in
                    ForEach(Array(zone.polygons.enumerated()), id: \.offset) { _, rings in
                        MapPolygon(coordinates: rings[0].map(\.location))
                            .foregroundStyle(Look.zone.opacity(0.07))
                            .stroke(Look.zone, lineWidth: 2)
                    }
                }
            }
            if let fix = game.location.fix, let target = game.target {
                MapPolyline(coordinates: [fix.coordinate.location, target.coordinate.location])
                    .stroke(Look.water, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [2, 9]))
            }
            ForEach(pins) { pin in
                Annotation("", coordinate: pin.head.coordinate.location, anchor: .center) {
                    Button {
                        selected = pin.head
                    } label: {
                        DrainMarker(tier: pin.tier, isTarget: game.target?.id == pin.head.id)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let fix = game.location.fix {
                Annotation("", coordinate: fix.coordinate.location, anchor: .center) {
                    PlayerDot()
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls { MapCompass() }
        .onMapCameraChange(frequency: .onEnd) { context in refresh(context.region) }
        .onChange(of: game.location.fix) { _, fix in
            if !centred, let fix { centre(on: fix.coordinate, metres: 420) }
        }
        .onChange(of: game.progress) { _, _ in redraw() }
        .onAppear(perform: open)
        .safeAreaInset(edge: .top) { TopBar(tooFar: tooFar) }
        .safeAreaInset(edge: .bottom) {
            GuideBar(onCatch: { head in begin(head) }, onLocate: {
                if let fix = game.location.fix { centre(on: fix.coordinate, metres: 420) }
            })
        }
        .sheet(item: $selected) { head in
            DrainSheet(head: head, onCatch: {
                selected = nil
                begin(head)
            }, onShow: {
                centre(on: head.coordinate, metres: 300)
            })
            .presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: $encounter) { head in
            EncounterView(head: head)
        }
        .sheet(item: $result) { result in
            ResultCard(result: result) { self.result = nil }
                .presentationDetents([.medium, .large])
        }
    }

    @State private var lastRegion: MKCoordinateRegion?

    private func refresh(_ region: MKCoordinateRegion) {
        lastRegion = region
        redraw()
    }

    /// Draw the drains of the part of the map that is on screen. From far away there would be hundreds of markers
    /// on top of each other, so then only the zones are drawn and a line says to come closer.
    private func redraw() {
        guard let region = lastRegion else { return }
        tooFar = region.span.latitudeDelta > 0.022
        guard !tooFar else {
            pins = []
            return
        }
        let half = (lat: region.span.latitudeDelta / 2, lon: region.span.longitudeDelta / 2)
        pins = game.pins(west: region.center.longitude - half.lon, south: region.center.latitude - half.lat,
                         east: region.center.longitude + half.lon, north: region.center.latitude + half.lat)
    }

    private func centre(on place: Coordinate, metres: Double) {
        centred = true
        withAnimation { camera = .region(MKCoordinateRegion(center: place.location, latitudinalMeters: metres, longitudinalMeters: metres)) }
    }

    /// A drain that rests has no creature, so the report is taken at once. Any other drain opens the catch.
    private func begin(_ head: Inlet) {
        if game.outlook(of: head)?.tier == .resting {
            result = game.settle(head, great: false)
        } else {
            encounter = head
        }
    }

    private func open() {
        if let fix = game.location.fix, !centred { centre(on: fix.coordinate, metres: 420) }
        guard let inlets = game.content?.inlets else { return }
        if let asked = game.opening.encounter, let head = inlets[asked] {
            game.opening.encounter = nil
            encounter = head
        } else if let asked = game.opening.select, let head = inlets[asked] {
            game.opening.select = nil
            selected = head
        }
    }
}

extension CatchResult: Identifiable {
    var id: UUID { record.id }
}

/// The player on the map.
struct PlayerDot: View {
    var body: some View {
        ZStack {
            Circle().fill(Color.blue.opacity(0.16)).frame(width: 46, height: 46)
            Circle().fill(.blue).frame(width: 16, height: 16).overlay(Circle().stroke(.white, lineWidth: 3))
        }
        .accessibilityLabel("You")
    }
}

/// The strip above the map with the player's level and points.
struct TopBar: View {
    @Environment(GameModel.self) private var game
    let tooFar: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Text("⛑️").font(.title2)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Apprentice, level \(game.standing?.level ?? 1)").font(.subheadline.weight(.semibold))
                    Text("\(Words.count(game.progress.points, "point", "points")), \(Words.count(Set(game.progress.catches.map(\.site)).count, "drain", "drains")) checked").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if game.stormOpen {
                    Label("Storm", systemImage: "cloud.bolt.rain.fill").font(.caption.weight(.semibold)).padding(6).background(Look.colour(of: .rare), in: Capsule()).foregroundStyle(.white)
                }
            }
            if tooFar {
                Text("Come closer to see the drains.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }
}

/// The strip under the map. It guides to the chosen drain, or names the best drain nearby when none is chosen.
struct GuideBar: View {
    @Environment(GameModel.self) private var game
    let onCatch: (Inlet) -> Void
    let onLocate: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let target = game.target {
                guide(to: target)
            } else {
                suggestion
            }
            Button(action: onLocate) {
                Image(systemName: "location.fill").font(.title3).frame(width: 44, height: 44).background(.thinMaterial, in: Circle())
            }
            .accessibilityLabel("Show where I am")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func guide(to target: Inlet) -> some View {
        let fence = game.fence(of: target)
        let turn = Geo.turn(fromHeading: game.location.heading ?? 0, toBearing: game.bearing(to: target) ?? 0)
        Image(systemName: "location.north.fill")
            .font(.title)
            .foregroundStyle(Look.water)
            .rotationEffect(.degrees(turn))
            .frame(width: 44, height: 44)
        VStack(alignment: .leading, spacing: 2) {
            Text(target.road.isEmpty ? "A drain" : target.road).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text(Words.fence(fence)).font(.caption).foregroundStyle(.secondary)
        }
        Spacer(minLength: 4)
        if case .inside = fence {
            Button("Catch") { onCatch(target) }.buttonStyle(.borderedProminent).tint(Look.water)
        } else {
            Button {
                game.target = nil
            } label: {
                Image(systemName: "xmark").frame(width: 36, height: 36).background(.thinMaterial, in: Circle())
            }
            .accessibilityLabel("Stop guiding")
        }
    }

    @ViewBuilder
    private var suggestion: some View {
        let near = game.nearby()
        let best = near.max { a, b in
            let ta = game.outlook(of: a.head)?.tier ?? .resting
            let tb = game.outlook(of: b.head)?.tier ?? .resting
            return ta == tb ? a.distanceM > b.distanceM : ta < tb
        }
        Image(systemName: "figure.walk").font(.title2).foregroundStyle(Look.water).frame(width: 44, height: 44)
        VStack(alignment: .leading, spacing: 2) {
            if game.location.fix == nil {
                Text("Waiting for your position.").font(.subheadline.weight(.semibold))
                Text(game.location.denied ? "Allow the position in Settings to play." : "The map needs it to find the drains around you.").font(.caption).foregroundStyle(.secondary)
            } else if let best, let tier = game.outlook(of: best.head)?.tier {
                Text("\(Words.name(of: tier)) drain, \(Words.distance(best.distanceM))").font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                Text("\(best.head.road.isEmpty ? "On a street nearby" : best.head.road). \(Words.count(near.count, "drain", "drains")) nearby.").font(.caption).foregroundStyle(.secondary).lineLimit(2).minimumScaleFactor(0.85)
            } else {
                Text("No drain of the game is near.").font(.subheadline.weight(.semibold))
                Text("The game is switched on inside the orange lines.").font(.caption).foregroundStyle(.secondary)
            }
        }
        Spacer(minLength: 4)
        if let best {
            Button("Guide me") { game.target = best.head }.buttonStyle(.bordered).tint(Look.water)
        }
    }
}
