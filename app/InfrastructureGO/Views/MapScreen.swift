import MapKit
import SwiftUI

/// The map of the game. The town lies under a pale veil that opens where the player walks. Drains appear as the
/// veil opens, what a drain holds shows only near the player, and the detector pulls toward the next one.
struct MapScreen: View {
    @Environment(GameModel.self) private var game
    @State private var camera: MapCameraPosition = .automatic
    @State private var following = true
    @State private var region: MKCoordinateRegion?
    @State private var tokens: [Token] = []
    @State private var sheet: MKPolygon?
    @State private var islands: [MKPolygon] = []
    @State private var selected: Inlet?
    @State private var meeting: Inlet?
    @State private var showsSettings = false
    @State private var showsDesk = false

    private let lookDown = MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: 40.3568, longitude: -74.6727), distance: 640, heading: 0, pitch: 36)

    var body: some View {
        MapReader { proxy in
            Map(position: $camera, bounds: bounds) {
                if let sheet {
                    MapPolygon(sheet).foregroundStyle(Look.paper.opacity(0.80)).mapOverlayLevel(level: .aboveRoads)
                }
                ForEach(Array(islands.enumerated()), id: \.offset) { _, island in
                    MapPolygon(island).foregroundStyle(Look.paper.opacity(0.80)).mapOverlayLevel(level: .aboveRoads)
                }
                if let zones = game.content?.zones.zones {
                    ForEach(zones) { zone in
                        ForEach(Array(zone.polygons.enumerated()), id: \.offset) { _, rings in
                            MapPolyline(coordinates: rings[0].map(\.location))
                                .stroke(Look.copper.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                        }
                    }
                }
                if let fix = game.location.fix, let target = game.target {
                    MapPolyline(coordinates: [fix.coordinate.location, target.coordinate.location])
                        .stroke(Look.creek, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [2, 9]))
                }
                ForEach(tokens) { token in
                    Annotation("", coordinate: token.head.coordinate.location, anchor: .center) {
                        Button {
                            selected = token.head
                            game.sound.play("select", volume: 0.4)
                        } label: {
                            TokenView(token: token, isTarget: game.target?.id == token.head.id, keepers: game.content?.keepers ?? [])
                        }
                        .buttonStyle(.plain)
                    }
                }
                ForEach(game.invitations) { invitation in
                    Annotation("", coordinate: invitation.head.coordinate.location, anchor: .bottom) {
                        Button {
                            game.target = invitation.head
                            following = true
                        } label: {
                            InvitationView(invitation: invitation)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let fix = game.location.fix {
                    Annotation("", coordinate: fix.coordinate.location, anchor: .center) {
                        PlayerMark(course: game.location.course)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .mapControls { MapCompass() }
            .onMapCameraChange(frequency: .onEnd) { context in
                region = context.region
                if camera.positionedByUser { following = false }
                redraw()
            }
            #if DEBUG
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.45).sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local)).onEnded { value in
                    if case .second(true, let drag?) = value, let place = proxy.convert(drag.location, from: .local) {
                        game.walk(to: Coordinate(lon: place.longitude, lat: place.latitude))
                        following = true
                    }
                }
            )
            #endif
        }
        .onChange(of: game.location.fix) { _, _ in
            follow()
            redraw()
        }
        .onChange(of: game.veilVersion) { _, _ in drawVeil() }
        .onChange(of: game.progress.meetings.count) { _, _ in redraw() }
        .onChange(of: game.progress.left) { _, _ in redraw() }
        .onChange(of: game.clockOffset) { _, _ in redraw() }
        .onAppear(perform: open)
        .safeAreaInset(edge: .top) {
            TopStrip(onSettings: { showsSettings = true }, onDesk: { showsDesk = true })
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if let said = game.announcement {
                    Button {
                        game.dismissAnnouncement()
                    } label: {
                        Text(said).font(.subheadline).foregroundStyle(Look.ink).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading).paperCard(padding: 12)
                    }
                    .buttonStyle(.plain)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if let head = game.drainAtHand {
                    LookButton(head: head) { meeting = head }
                }
                if game.showsNearby, !game.shadows.isEmpty {
                    NearbyStrip { head in
                        game.target = head
                        following = true
                        follow()
                    }
                }
                DetectorStrip(following: following) {
                    following = true
                    follow()
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            .animation(.easeOut(duration: 0.25), value: game.announcement)
        }
        .sheet(item: $selected) { head in
            DrainSheet(head: head) {
                selected = nil
                meeting = head
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showsSettings) {
            SettingsSheet().presentationDetents([.medium, .large])
        }
        #if DEBUG
        .sheet(isPresented: $showsDesk) {
            DeskPanel().presentationDetents([.medium])
        }
        #endif
        .fullScreenCover(item: $meeting) { head in
            EncounterView(head: head)
        }
    }

    /// The camera may not leave the town, so that the edge of the veil's sheet is never seen.
    private var bounds: MapCameraBounds? {
        guard let box = townBox else { return nil }
        let middle = CLLocationCoordinate2D(latitude: (box.south + box.north) / 2, longitude: (box.west + box.east) / 2)
        let span = MKCoordinateSpan(latitudeDelta: box.north - box.south, longitudeDelta: box.east - box.west)
        return MapCameraBounds(centerCoordinateBounds: MKCoordinateRegion(center: middle, span: span), minimumDistance: 150, maximumDistance: 6000)
    }

    /// The box around all zones of the game.
    private var townBox: (west: Double, south: Double, east: Double, north: Double)? {
        guard let zones = game.content?.zones.zones else { return nil }
        let points = zones.flatMap { $0.polygons.flatMap { $0.first ?? [] } }
        guard let west = points.map(\.lon).min(), let east = points.map(\.lon).max(), let south = points.map(\.lat).min(), let north = points.map(\.lat).max() else { return nil }
        return (west, south, east, north)
    }

    private func open() {
        drawVeil()
        follow()
        guard let inlets = game.content?.inlets else { return }
        if let asked = game.opening.encounter, let head = inlets[asked] {
            game.opening.encounter = nil
            meeting = head
        } else if let asked = game.opening.select, let head = inlets[asked] {
            game.opening.select = nil
            selected = head
        }
    }

    private func follow() {
        guard following, let fix = game.location.fix else { return }
        withAnimation(.linear(duration: 0.3)) {
            camera = .camera(MapCamera(centerCoordinate: fix.coordinate.location, distance: lookDown.distance, heading: 0, pitch: lookDown.pitch))
        }
    }

    private func redraw() {
        guard let region else { return }
        let half = (lat: region.span.latitudeDelta / 2, lon: region.span.longitudeDelta / 2)
        tokens = game.tokens(west: region.center.longitude - half.lon, south: region.center.latitude - half.lat,
                             east: region.center.longitude + half.lon, north: region.center.latitude + half.lat)
    }

    /// Build the veil's sheet, one large piece with a hole for every patch of open ground. It reaches far beyond
    /// the town on every side.
    private func drawVeil() {
        guard let box = townBox else { return }
        let far = 0.25
        var outer = [CLLocationCoordinate2D(latitude: box.south - far, longitude: box.west - far), CLLocationCoordinate2D(latitude: box.south - far, longitude: box.east + far),
                     CLLocationCoordinate2D(latitude: box.north + far, longitude: box.east + far), CLLocationCoordinate2D(latitude: box.north + far, longitude: box.west - far)]
        let holes = game.veil.holes.map { ring -> MKPolygon in
            var points = ring.map(\.location)
            return MKPolygon(coordinates: &points, count: points.count)
        }
        sheet = MKPolygon(coordinates: &outer, count: outer.count, interiorPolygons: holes)
        islands = game.veil.islands.map { ring -> MKPolygon in
            var points = ring.map(\.location)
            return MKPolygon(coordinates: &points, count: points.count)
        }
    }
}

/// A drain on the map.
struct TokenView: View {
    let token: Token
    let isTarget: Bool
    let keepers: [Keeper]

    var body: some View {
        ZStack {
            switch token.state {
            case .plain:
                Circle().fill(Look.paper).frame(width: 15, height: 15).overlay(Circle().stroke(Look.copper, lineWidth: 3))
            case .resting:
                Circle().fill(Look.paperDeep).frame(width: 18, height: 18)
                    .overlay(Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(Look.inkSoft))
                    .overlay(Circle().stroke(Look.ink.opacity(0.25), lineWidth: 1.5))
            case .holds(let keeper, let met, let crate):
                let kind = keepers.first { $0.id == keeper }?.kind ?? "common"
                KeeperFace(keeper: keeper, met: met, size: 44, ring: met ? Look.colour(ofKind: kind) : Look.ink.opacity(0.35))
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                if crate > 0 {
                    Image(systemName: "shippingbox.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(Look.paper)
                        .padding(4).background(Look.copper, in: Circle()).overlay(Circle().stroke(Look.paper, lineWidth: 1.5)).offset(x: 17, y: 15)
                }
            }
            if isTarget {
                Circle().stroke(Look.marigold, lineWidth: 4).frame(width: 56, height: 56)
            }
        }
        .frame(width: 58, height: 58)
        .contentShape(Circle())
        .accessibilityLabel(label)
    }

    private var label: String {
        switch token.state {
        case .plain: "A drain you found"
        case .resting: "A drain you looked at today"
        case .holds(_, let met, _): met ? "A keeper you know is here" : "Someone you have not met is here"
        }
    }
}

/// An invitation above the veil: a keeper that waits for the player, or the light of the week's visitor.
struct InvitationView: View {
    let invitation: Invitation
    @State private var glow = false

    var body: some View {
        VStack(spacing: 0) {
            if invitation.isVisitor {
                ZStack(alignment: .bottom) {
                    Capsule()
                        .fill(LinearGradient(colors: [Look.verdigris.opacity(0), Look.verdigris.opacity(glow ? 0.9 : 0.55)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 16, height: 110)
                    Image(systemName: "sparkle").font(.system(size: 20, weight: .bold)).foregroundStyle(Look.paper).offset(y: -96)
                }
            }
            KeeperFace(keeper: invitation.keeper.id, met: invitation.showsKeeper, size: 42, ring: invitation.isVisitor ? Look.verdigris : Look.marigold)
                .overlay(Circle().stroke((invitation.isVisitor ? Look.verdigris : Look.marigold).opacity(glow ? 0 : 0.7), lineWidth: 3).scaleEffect(glow ? 1.5 : 1))
                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
            Text(invitation.isVisitor ? "This week's visitor" : "Waits for you")
                .font(.caption2.weight(.semibold)).foregroundStyle(Look.ink)
                .padding(.horizontal, 6).padding(.vertical, 2).background(Look.paper, in: Capsule())
        }
        .onAppear { withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: false)) { glow = true } }
        .accessibilityLabel(invitation.isVisitor ? "The visitor of the week" : "A keeper that slipped away waits here")
    }
}

/// The player on the map, with the way they face.
struct PlayerMark: View {
    let course: Double?

    var body: some View {
        ZStack {
            Circle().fill(Look.creek.opacity(0.14)).frame(width: 52, height: 52)
            if let course {
                Image(systemName: "arrowtriangle.up.fill").font(.system(size: 13)).foregroundStyle(Look.creek).offset(y: -18).rotationEffect(.degrees(course))
            }
            Circle().fill(Look.creek).frame(width: 18, height: 18).overlay(Circle().stroke(Look.paper, lineWidth: 3))
        }
        .accessibilityLabel("You")
    }
}

/// The strip above the map: the apprentice, the level and how much of the town is found.
struct TopStrip: View {
    @Environment(GameModel.self) private var game
    let onSettings: () -> Void
    let onDesk: () -> Void

    var body: some View {
        let found = game.found
        HStack(spacing: 10) {
            WorkerBadge(figure: game.progress.figure, vest: game.opens("more_shadows"), size: 42)
            VStack(alignment: .leading, spacing: 3) {
                if let standing = game.standing {
                    Text("\(standing.rank), level \(standing.level)").font(.subheadline.weight(.semibold)).foregroundStyle(Look.ink)
                    ProgressView(value: standing.fraction).tint(Look.creek).frame(maxWidth: 150)
                }
                HStack(spacing: 8) {
                    Text("\(found.known) of \(found.all) drains found")
                    if game.showsJobs {
                        let open = game.progress.jobs.filter { !$0.isFinished }.count
                        Label(Words.count(open, "job", "jobs"), systemImage: "checklist")
                    }
                }
                .font(.caption).foregroundStyle(Look.inkSoft)
            }
            Spacer(minLength: 4)
            if let friend = game.progress.friend {
                KeeperFace(keeper: friend, met: true, size: 36, ring: Look.moss)
            }
            #if DEBUG
            Button(action: onDesk) {
                Image(systemName: "wrench.adjustable.fill").frame(width: 36, height: 36).background(Look.paperDeep, in: Circle())
            }
            .accessibilityLabel("The desk panel")
            #endif
            Button(action: onSettings) {
                Image(systemName: "gearshape.fill").frame(width: 36, height: 36).background(Look.paperDeep, in: Circle())
            }
            .accessibilityLabel("Settings")
        }
        .foregroundStyle(Look.ink)
        .paperCard(padding: 10)
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }
}

/// The one large button that starts a meeting, shown when the player stands at a drain that holds something.
struct LookButton: View {
    @Environment(GameModel.self) private var game
    let head: Inlet
    let action: () -> Void

    var body: some View {
        let who = game.keeper(at: head)
        let met = who.map { game.progress.met.contains($0.id) } ?? false
        VStack(spacing: 8) {
            if !game.hasMetAnyone {
                Text("Someone is peeking out. Stop somewhere safe and take a look.").font(.subheadline.weight(.semibold)).foregroundStyle(Look.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(action: action) {
                HStack(spacing: 12) {
                    KeeperFace(keeper: who?.id, met: met, size: 40)
                    Text("Take a look").font(.title3.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right").font(.headline)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 60)
            }
            .buttonStyle(.borderedProminent)
            .tint(Look.creek)
        }
        .paperCard(padding: 10)
    }
}

/// The strip of shadows: the keepers near the player, also under the veil. A tap picks one to walk to.
struct NearbyStrip: View {
    @Environment(GameModel.self) private var game
    let onPick: (Inlet) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("Near you").font(.caption.weight(.semibold)).foregroundStyle(Look.inkSoft)
            ForEach(game.shadows) { shadow in
                Button {
                    onPick(shadow.head)
                    game.sound.play("select", volume: 0.4)
                } label: {
                    VStack(spacing: 2) {
                        KeeperFace(keeper: shadow.keeper.id, met: shadow.met, size: 40,
                                   ring: game.target?.id == shadow.head.id ? Look.marigold : shadow.met ? Look.colour(ofKind: shadow.keeper.kind) : Look.ink.opacity(0.3))
                        Text(Words.distance(shadow.distanceM)).font(.caption2).foregroundStyle(Look.ink)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(shadow.met ? "\(shadow.keeper.name), \(Words.distance(shadow.distanceM)) away" : "Someone you have not met, \(Words.distance(shadow.distanceM)) away")
            }
            Spacer(minLength: 0)
        }
        .paperCard(padding: 9)
    }
}

/// The detector at the bottom of the map. Its needle points at the nearest drain that still holds something, or
/// at the drain the player chose, and it kicks with every tick.
struct DetectorStrip: View {
    @Environment(GameModel.self) private var game
    let following: Bool
    let onLocate: () -> Void
    @State private var kick = false

    var body: some View {
        let reading = game.reading
        HStack(spacing: 12) {
            dial(reading)
            VStack(alignment: .leading, spacing: 2) {
                if let target = game.target {
                    Text(target.road.isEmpty ? "A drain" : target.road).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(Words.fence(game.fence(of: target))).font(.caption).foregroundStyle(Look.inkSoft)
                } else {
                    Text(Words.detector(reading)).font(.subheadline.weight(.semibold)).lineLimit(2).minimumScaleFactor(0.85)
                    if game.opens("tuned"), let kind = reading.kind, reading.state == .signal {
                        Text("It sounds like a \(Look.word(forKind: kind).lowercased()) keeper.").font(.caption).foregroundStyle(Look.inkSoft)
                    } else if let hint = game.huntLine {
                        Text(hint).font(.caption).foregroundStyle(Look.inkSoft).lineLimit(2)
                    }
                }
                #if targetEnvironment(simulator)
                if !game.isWalking {
                    Text("At your desk: press and hold the map to walk there.").font(.caption2).foregroundStyle(Look.copper)
                }
                #endif
            }
            .foregroundStyle(Look.ink)
            Spacer(minLength: 2)
            if game.target != nil {
                Button {
                    game.target = nil
                } label: {
                    Image(systemName: "xmark").frame(width: 36, height: 36).background(Look.paperDeep, in: Circle())
                }
                .accessibilityLabel("Stop leading me")
            }
            if !following {
                Button(action: onLocate) {
                    Image(systemName: "location.fill").frame(width: 36, height: 36).background(Look.paperDeep, in: Circle())
                }
                .accessibilityLabel("Show where I am")
            }
        }
        .foregroundStyle(Look.ink)
        .paperCard(padding: 10)
        .onChange(of: game.ticks) { _, _ in
            kick = true
            withAnimation(.easeOut(duration: 0.22)) { kick = false }
        }
    }

    private func dial(_ reading: Reading) -> some View {
        let toward = game.target.flatMap { game.bearing(to: $0) } ?? reading.bearing
        let turn = toward.map { Geo.turn(fromHeading: game.location.course ?? 0, toBearing: $0) }
        let strength = game.target != nil ? 0.6 : reading.strength
        let live = game.target != nil || reading.state == .signal || reading.state == .atDrain
        let tint = game.opens("tuned") ? Look.colour(ofKind: reading.kind ?? "common") : Look.verdigris
        return ZStack {
            Circle().fill(Look.paperDeep)
            Circle().trim(from: 0, to: live ? max(0.04, strength) : 0).stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90)).padding(3)
            if let turn, live {
                Image(systemName: "location.north.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(Look.creek).rotationEffect(.degrees(turn))
            } else {
                Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 17, weight: .semibold)).foregroundStyle(Look.inkSoft)
            }
        }
        .frame(width: 52, height: 52)
        .scaleEffect(kick ? 1.14 : 1)
        .accessibilityLabel("The detector")
    }
}
