import Foundation

/// Where the camera stood when the picture behind a meeting was taken, and where the grate lies in front of it.
///
/// On a phone the camera's own picture stands behind a meeting. The simulator has no camera, so there a photograph
/// of a real drain takes its place, and this is what lets a keeper sit on the photographed grate at its true size.
/// The camera stands above the origin of the ground at its height, looks along minus z and is tilted down by its
/// pitch. Everything here is plain arithmetic of a pinhole camera, so that aiming can be tested without a screen.
nonisolated struct Backdrop: Sendable, Decodable, Equatable, Identifiable {
    let id: String
    let file: String
    let aspect: Double              // of the picture, width over height
    let fovVerticalDeg: Double      // what the whole picture sees from top to bottom
    let pitchDeg: Double
    let heightM: Double
    let grateXM: Double
    let grateZM: Double
    let grateYawDeg: Double
    let grateLengthM: Double        // along the kerb
    let grateDepthM: Double         // from the kerb into the street

    /// The view onto the modelled drain that the app builds itself when no photograph is there.
    static let modelled = Backdrop(id: "modelled", file: "", aspect: 0.45, fovVerticalDeg: 68, pitchDeg: 43, heightM: 1.75,
                                   grateXM: 0, grateZM: -1.7, grateYawDeg: 0, grateLengthM: 1.16, grateDepthM: 0.64)

    /// The vertical field of view a camera needs so that the picture fills a screen without bars. A screen that is
    /// wider than the picture cuts from its top and bottom, a narrower one from its sides.
    func cameraFovDeg(screenAspect: Double) -> Double {
        guard screenAspect > aspect, screenAspect > 0 else { return fovVerticalDeg }
        let half = atan(tan(fovVerticalDeg * .pi / 360) * aspect / screenAspect)
        return half * 360 / .pi
    }

    /// Where a point of the ground appears on the screen, as fractions from the left and from the top, or nil for
    /// a point behind the camera.
    func project(x: Double, z: Double, lift: Double = 0, screenAspect: Double) -> (u: Double, v: Double)? {
        let pitch = pitchDeg * .pi / 180
        let depth = (heightM - lift) * sin(pitch) - z * cos(pitch)
        guard depth > 0.01 else { return nil }
        let up = -(heightM - lift) * cos(pitch) - z * sin(pitch)
        let focal = 0.5 / tan(cameraFovDeg(screenAspect: screenAspect) * .pi / 360)
        return (0.5 + x / depth * focal / screenAspect, 0.5 - up / depth * focal)
    }

    /// The point of the ground under a point of the screen, or nil when the screen point looks above the horizon.
    func ground(u: Double, v: Double, screenAspect: Double) -> (x: Double, z: Double)? {
        let pitch = pitchDeg * .pi / 180
        let focal = 0.5 / tan(cameraFovDeg(screenAspect: screenAspect) * .pi / 360)
        let right = (u - 0.5) * screenAspect / focal
        let rise = (0.5 - v) / focal
        // The ray through the screen point, in the ground's axes: one step forward, right to the side, rise upward.
        let down = sin(pitch) - rise * cos(pitch)
        guard down > 0.001 else { return nil }
        let reach = heightM / down
        return (right * reach, -(cos(pitch) + rise * sin(pitch)) * reach)
    }

    /// A place on the grate. Along runs from minus one at its left end to one at its right end as the camera
    /// sees it, across from minus one at the kerb to one at the street side.
    func spot(along: Double, across: Double) -> (x: Double, z: Double) {
        let yaw = grateYawDeg * .pi / 180
        let a = along * grateLengthM / 2
        let b = across * grateDepthM / 2
        return (grateXM + a * cos(yaw) - b * sin(yaw), grateZM + a * sin(yaw) + b * cos(yaw))
    }
}

nonisolated struct BackdropFile: Sendable, Decodable {
    let backdrops: [Backdrop]

    init(json: Data) throws {
        self = try GameData.decoder.decode(BackdropFile.self, from: json)
    }
}
