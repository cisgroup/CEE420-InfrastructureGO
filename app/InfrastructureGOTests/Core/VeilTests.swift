import Foundation
import Testing
@testable import InfrastructureGO

@Suite("The veil over the town")
struct VeilTests {
    let grid = VeilGrid(origin: Coordinate(lon: -74.75, lat: 40.30), cellM: 25)
    let mountain = Coordinate(lon: -74.672675, lat: 40.356792)

    func block(_ xs: ClosedRange<Int>, _ ys: ClosedRange<Int>, without: [(Int, Int)] = []) -> Set<Int64> {
        var cells: Set<Int64> = []
        for x in xs { for y in ys where !without.contains(where: { $0 == (x, y) }) { cells.insert(VeilGrid.key(x, y)) } }
        return cells
    }

    @Test func aSquareHasANumberAndComesBackFromIt() {
        for (x, y) in [(0, 0), (12, 340), (-3, 7), (5, -9), (-40, -41), (100_000, 99_999)] {
            let back = VeilGrid.place(VeilGrid.key(x, y))
            #expect(back.x == x && back.y == y)
        }
        #expect(grid.cell(of: mountain) == grid.cell(of: Coordinate(lon: mountain.lon + 0.00001, lat: mountain.lat)))
    }

    @Test func aSquareIsItsSizeAcross() {
        let at = grid.place(of: mountain)
        let west = grid.position(x: Double(at.x), y: Double(at.y)), east = grid.position(x: Double(at.x + 1), y: Double(at.y))
        let north = grid.position(x: Double(at.x), y: Double(at.y + 1))
        #expect(abs(Geo.distance(west, east) - 25) < 0.1 && abs(Geo.distance(west, north) - 25) < 0.1)
    }

    @Test func walkingOpensARoundPatchThatStaysOpen() {
        var cells: Set<Int64> = []
        let fresh = Veil.open(&cells, around: mountain, radiusM: 70, grid: grid)
        let expected = Double.pi * 70 * 70 / (25 * 25)
        #expect(Double(fresh) > expected * 0.8 && Double(fresh) < expected * 1.2)
        #expect(Veil.open(&cells, around: mountain, radiusM: 70, grid: grid) == 0, "ground that is open is not opened again")
        #expect(Veil.isOpen(mountain, cells: cells, grid: grid))
        #expect(!Veil.isOpen(Coordinate(lon: mountain.lon + 0.002, lat: mountain.lat), cells: cells, grid: grid))
        let further = Veil.open(&cells, around: Coordinate(lon: mountain.lon + 0.0005, lat: mountain.lat), radiusM: 70, grid: grid)
        #expect(further > 0 && further < fresh, "a step further opens only the new edge")
    }

    @Test func oneSquareHasOneLoopAgainstTheClock() {
        let loops = Veil.loops(of: [VeilGrid.key(4, 4)])
        #expect(loops.count == 1 && loops[0].count == 4)
        #expect(Veil.twiceArea(loops[0].map { (Double($0.x), Double($0.y)) }) == 2)
        #expect(Veil.loops(of: []).isEmpty)
    }

    @Test func squaresThatTouchAtACornerStayApart() {
        let loops = Veil.loops(of: [VeilGrid.key(0, 0), VeilGrid.key(1, 1)])
        #expect(loops.count == 2 && loops.allSatisfy { $0.count == 4 })
    }

    @Test func aBlockIsOneLoopAroundAllOfIt() {
        let loops = Veil.loops(of: block(0...3, 0...2))
        #expect(loops.count == 1 && loops[0].count == 14)
        #expect(Veil.twiceArea(loops[0].map { (Double($0.x), Double($0.y)) }) == 24)
    }

    @Test func coveredGroundInsideOpenGroundIsAnIsland() {
        let cells = block(0...2, 0...2, without: [(1, 1)])
        let loops = Veil.loops(of: cells)
        let areas = loops.map { Veil.twiceArea($0.map { (Double($0.x), Double($0.y)) }) }.sorted()
        #expect(areas == [-2, 18], "the island runs with the clock, the open ground against it")
        let rings = Veil.rings(of: cells, grid: grid)
        #expect(rings.holes.count == 1 && rings.islands.count == 1)
    }

    @Test func theDrawnEdgeIsRoundAndKeepsTheGround() {
        var cells: Set<Int64> = []
        Veil.open(&cells, around: mountain, radiusM: 70, grid: grid)
        let loop = try! #require(Veil.loops(of: cells).first)
        let smooth = Veil.rounded(loop, cuts: 2)
        #expect(smooth.count == loop.count * 4)
        let kept = Veil.twiceArea(smooth) / 2 / Double(cells.count)
        #expect(kept > 0.85 && kept <= 1.0, "rounding cuts corners and nothing else, it kept \(kept) of the ground")
        // No corner of the drawn edge is a right angle any more.
        for k in smooth.indices {
            let a = smooth[k], b = smooth[(k + 1) % smooth.count], c = smooth[(k + 2) % smooth.count]
            let turn = abs(atan2((b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x), (b.x - a.x) * (c.x - b.x) + (b.y - a.y) * (c.y - b.y))) * 180 / .pi
            #expect(turn < 50)
        }
        let rings = Veil.rings(of: cells, grid: grid)
        #expect(rings.holes.count == 1 && rings.islands.isEmpty)
        let far = rings.holes[0].map { Geo.distance(mountain, $0) }.max() ?? 0
        #expect(far > 55 && far < 95)
    }

    @Test func theOpenGroundSurvivesBeingSaved() throws {
        var progress = PlayerProgress()
        Veil.open(&progress.openCells, around: mountain, radiusM: 110, grid: grid)
        let back = try JSONDecoder().decode(PlayerProgress.self, from: JSONEncoder().encode(progress))
        #expect(back.openCells == progress.openCells && !back.openCells.isEmpty)
    }
}
