import CoreLocation
import Combine
import Foundation

@MainActor
final class LocationTelemetryManager: NSObject, ObservableObject {
    static let shared = LocationTelemetryManager()

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var location: CLLocation?
    @Published private(set) var errorMessage: String?

    private let manager = CLLocationManager()

    override private init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled else {
            manager.stopUpdatingLocation()
            return
        }

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            errorMessage = "Location access is disabled in iOS Settings."
        @unknown default:
            errorMessage = "Location access is unavailable."
        }
    }

    func refresh() {
        guard manager.authorizationStatus == .authorizedAlways
                || manager.authorizationStatus == .authorizedWhenInUse
        else {
            setEnabled(true)
            return
        }

        manager.requestLocation()
    }
}

extension LocationTelemetryManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus

            if manager.authorizationStatus == .authorizedAlways
                || manager.authorizationStatus == .authorizedWhenInUse {
                errorMessage = nil
                manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let newest = locations.last else {
            return
        }

        Task { @MainActor in
            location = newest
            errorMessage = nil
            let sharingEnabled = UserDefaults.standard.bool(
                forKey: TelemetryPreferenceKey.shareLocation
            )
            ReticulumCoreBridge.shared.setAnnounceLocation(
                sharingEnabled ? newest : nil
            )
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        let locationError = error as? CLError
        guard locationError?.code != .locationUnknown else {
            return
        }

        Task { @MainActor in
            errorMessage = error.localizedDescription
        }
    }
}
