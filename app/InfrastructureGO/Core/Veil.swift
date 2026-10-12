import Foundation

/// The veil over the town. Ground a player never walked is covered, ground they walked is open for good.
///
/// The open ground is kept as squares of a grid, each named by one number. The squares a player opened are a
/// trace of where that player walked. They are kept on the phone and nowhere else, they are never sent anywhere
/// and never drawn into a picture that another person sees.
nonisolated struct VeilGrid: Sendable, Equatable {
    let origin: Coordinate
    let cellM: Double
    private let lonStep: Double
    private let latStep: Double

    init(origin: Coordinate, cellM: Double) {
        self.origin = origin
        self.cellM = cellM
        let probe = Geo.offset(from: origin, to: Coordinate(lon: origin.lon + 0.01, lat: origin.lat + 0.01))
        lonStep = cellM * 0.01 / probe.east
        latStep = cellM * 0.01 / probe.north
    }

    static func key(_ x: Int, _ y: Int) -> Int64 {
        Int64(x) << 32 | Int64(UInt32(truncatingIfNeeded: y))
    }

    static func place(_ key: Int64) -> (x: Int, y: Int) {
        (Int(key >> 32), Int(Int32(truncatingIfNeeded: key)))
    }

    func place(of position: Coordinate) -> (x: Int, y: Int) {
        (Int(((position.lon - origin.lon) / lonStep).rounded(.down)), Int(((position.lat - origin.lat) / latStep).rounded(.down)))
    }

    func cell(of position: Coordinate) -> Int64 {
        let at = place(of: position)
        return Self.key(at.x, at.y)
    }

    /// The position of a corner of the grid, where x and y may lie between corners.
    func position(x: Double, y: Double) -> Coordinate {
        Coordinate(lon: origin.lon + x * lonStep, lat: origin.lat + y * latStep)
    }

    /// The squares whose middle lies within a radius of a position.
    func cells(around position: Coordinate, radiusM: Double) -> [Int64] {
        let here = place(of: position)
        let reach = Int((radiusM / cellM).rounded(.up)) + 1
        var found: [Int64] = []
        for x in (here.x - reach)...(here.x + reach) {
            for y in (here.y - reach)...(here.y + reach) where Geo.distance(position, self.position(x: Double(x) + 0.5, y: Double(y) + 0.5)) <= radiusM {
                found.append(Self.key(x, y))
            }
        }
        return found
    }
}

nonisolated enum Veil {
    /// Open the ground around a position. Returns how many squares were new.
    @discardableResult
    static func open(_ cells: inout Set<Int64>, around position: Coordinate, radiusM: Double, grid: VeilGrid) -> Int {
        var fresh = 0
        for cell in grid.cells(around: position, radiusM: radiusM) where cells.insert(cell).inserted { fresh += 1 }
        return fresh
    }

    static func isOpen(_ position: Coordinate, cells: Set<Int64>, grid: VeilGrid) -> Bool {
        cells.contains(grid.cell(of: position))
    }

    /// The edges between open and covered ground as closed loops of grid corners. Open ground lies to the left of
    /// every loop, so a loop around open ground runs against the clock and a loop around a covered island inside
    /// open ground runs with it. Squares that touch only at a corner are not joined.
    static func loops(of cells: Set<Int64>) -> [[(x: Int, y: Int)]] {
        struct Corner: Hashable { let x: Int; let y: Int }
        var leaving: [Corner: [Corner]] = [:]
        for cell in cells {
            let at = VeilGrid.place(cell)
            let (x, y) = (at.x, at.y)
            if !cells.contains(VeilGrid.key(x, y - 1)) { leaving[Corner(x: x, y: y), default: []].append(Corner(x: x + 1, y: y)) }
            if !cells.contains(VeilGrid.key(x + 1, y)) { leaving[Corner(x: x + 1, y: y), default: []].append(Corner(x: x + 1, y: y + 1)) }
            if !cells.contains(VeilGrid.key(x, y + 1)) { leaving[Corner(x: x + 1, y: y + 1), default: []].append(Corner(x: x, y: y + 1)) }
            if !cells.contains(VeilGrid.key(x - 1, y)) { leaving[Corner(x: x, y: y + 1), default: []].append(Corner(x: x, y: y)) }
        }
        var loops: [[(x: Int, y: Int)]] = []
        let starts = leaving.keys.sorted { ($0.x, $0.y) < ($1.x, $1.y) }
        for start in starts {
            while let first = leaving[start]?.popLast() {
                var loop = [start]
                var before = start
                var here = first
                while here != start {
                    loop.append(here)
                    guard var ways = leaving[here], !ways.isEmpty else { break }
                    // Where two loops meet at a corner, turn left, which keeps to the square the loop came along.
                    let ahead = (x: here.x - before.x, y: here.y - before.y)
                    let pick = ways.firstIndex { ($0.x - here.x, $0.y - here.y) == (-ahead.y, ahead.x) } ?? ways.firstIndex { ($0.x - here.x, $0.y - here.y) == (ahead.x, ahead.y) } ?? 0
                    let next = ways.remove(at: pick)
                    leaving[here] = ways
                    before = here
                    here = next
                }
                loops.append(loop.map { (x: $0.x, y: $0.y) })
            }
        }
        return loops
    }

    /// Twice the area a loop encloses in squares, positive when it runs against the clock.
    static func twiceArea(_ loop: [(x: Double, y: Double)]) -> Double {
        var sum = 0.0
        for k in loop.indices {
            let a = loop[k], b = loop[(k + 1) % loop.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum
    }

    /// A loop with its steps rounded off. The middles of its edges are joined first, which turns a staircase into
    /// a slope, and then every corner is cut the given number of times.
    static func rounded(_ loop: [(x: Int, y: Int)], cuts: Int) -> [(x: Double, y: Double)] {
        var points: [(x: Double, y: Double)] = loop.indices.map { k in
            let a = loop[k], b = loop[(k + 1) % loop.count]
            return (Double(a.x + b.x) / 2, Double(a.y + b.y) / 2)
        }
        for _ in 0..<max(0, cuts) {
            var cut: [(x: Double, y: Double)] = []
            cut.reserveCapacity(points.count * 2)
            for k in points.indices {
                let a = points[k], b = points[(k + 1) % points.count]
                cut.append((0.75 * a.x + 0.25 * b.x, 0.75 * a.y + 0.25 * b.y))
                cut.append((0.25 * a.x + 0.75 * b.x, 0.25 * a.y + 0.75 * b.y))
            }
            points = cut
        }
        return points
    }

    /// What the map draws. The veil is one sheet with a hole for every patch of open ground, and every covered
    /// island inside open ground is a small sheet of its own.
    static func rings(of cells: Set<Int64>, grid: VeilGrid, cuts: Int = 2) -> (holes: [[Coordinate]], islands: [[Coordinate]]) {
        var holes: [[Coordinate]] = []
        var islands: [[Coordinate]] = []
        for loop in loops(of: cells) {
            let smooth = rounded(loop, cuts: cuts)
            let ring = smooth.map { grid.position(x: $0.x, y: $0.y) }
            if twiceArea(loop.map { (Double($0.x), Double($0.y)) }) > 0 { holes.append(ring) } else { islands.append(ring) }
        }
        return (holes, islands)
    }
}
