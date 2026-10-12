import CoreLocation
import Foundation
import Observation

/// Where the phone is, with how sure it is.
nonisolated struct Fix: Sendable, Equatable {
    let coordinate: Coordinate
    let accuracyM: Double
}

extension Coordinate {
    var location: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}

/// The phone's position and heading. In a debug build a position can be set by hand, so that the game can be
/// tried in the simulator and at a desk without walking.
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var measured: Fix?
    private(set) var heading: Double?
    private(set) var denied = false
    var standIn: Fix?
    var standInCourse: Double?

    /// The position the game plays with.
    var fix: Fix? { standIn ?? measured }

    /// The direction the player faces, in degrees clockwise from north. At a desk it is the direction of the walk.
    var course: Double? { standIn != nil ? standInCourse : heading }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last, last.horizontalAccuracy >= 0 else { return }
        let fix = Fix(coordinate: Coordinate(lon: last.coordinate.longitude, lat: last.coordinate.latitude), accuracyM: last.horizontalAccuracy)
        Task { @MainActor in self.measured = fix }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let degrees = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in self.heading = degrees }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.denied = status == .denied || status == .restricted
            if status == .authorizedWhenInUse || status == .authorizedAlways { manager.startUpdatingLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("The position could not be read, \(error.localizedDescription)")
    }
}
