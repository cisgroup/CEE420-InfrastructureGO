import Foundation
import Testing
@testable import InfrastructureGO

@Suite("The backdrop's camera")
struct BackdropTests {
    let phone = 1206.0 / 2622.0

    @Test("The grate of the modelled drain lies in the lower middle of the screen")
    func grateIsInView() throws {
        let seen = try #require(Backdrop.modelled.project(x: 0, z: Backdrop.modelled.grateZM, screenAspect: phone))
        #expect(abs(seen.u - 0.5) < 0.001)
        #expect(seen.v > 0.4 && seen.v < 0.7)
    }

    @Test("A point of the ground comes back from its place on the screen")
    func roundTrip() throws {
        let view = Backdrop(id: "t", file: "", aspect: 0.45, fovVerticalDeg: 83.3, pitchDeg: 42, heightM: 1.37, grateXM: -0.03, grateZM: -1.23,
                            grateYawDeg: 1.7, grateLengthM: 1.2, grateDepthM: 0.6)
        for (x, z) in [(0.0, -1.2), (0.5, -0.9), (-0.6, -1.6), (0.2, -3.0)] {
            let seen = try #require(view.project(x: x, z: z, screenAspect: phone))
            let back = try #require(view.ground(u: seen.u, v: seen.v, screenAspect: phone))
            #expect(abs(back.x - x) < 1e-9 && abs(back.z - z) < 1e-9)
        }
    }

    @Test("A screen point above the horizon has no ground under it, and a point behind the camera is not seen")
    func noGround() {
        #expect(Backdrop.modelled.ground(u: 0.5, v: -2.0, screenAspect: phone) == nil)
        #expect(Backdrop.modelled.project(x: 0, z: 5, screenAspect: phone) == nil)
    }

    @Test("A screen wider than the picture sees less from top to bottom, a narrower one sees the picture's height")
    func fieldOfView() {
        let view = Backdrop.modelled
        #expect(view.cameraFovDeg(screenAspect: 0.40) == view.fovVerticalDeg)
        #expect(view.cameraFovDeg(screenAspect: 0.5625) < view.fovVerticalDeg)
    }

    @Test("The ends of the grate lie its length apart, and the street side is nearer to the camera than the kerb")
    func spots() {
        let view = Backdrop.modelled
        let left = view.spot(along: -1, across: 0), right = view.spot(along: 1, across: 0)
        #expect(abs(hypot(right.x - left.x, right.z - left.z) - view.grateLengthM) < 1e-9)
        #expect(view.spot(along: 0, across: 1).z > view.spot(along: 0, across: -1).z)
    }

    @Test("The file of backdrops is read with its underscored keys")
    func decodes() throws {
        let json = #"{"about": "x", "backdrops": [{"id": "p1", "file": "backdrop_p1", "aspect": 0.45, "fov_vertical_deg": 83.3, "pitch_deg": 42.0, "height_m": 1.37, "grate_x_m": -0.03, "grate_z_m": -1.23, "grate_yaw_deg": 1.7, "grate_length_m": 1.2, "grate_depth_m": 0.6, "worst_miss": 0.01}]}"#
        let file = try BackdropFile(json: Data(json.utf8))
        #expect(file.backdrops.first?.heightM == 1.37)
    }
}
