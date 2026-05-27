import CoreLocation
import Foundation

@MainActor
final class LocationPermissionManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
    }

    func requestWiFiAccessIfNeeded() {
        switch currentAuthorizationStatus() {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse, .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    func currentAuthorizationStatus() -> CLAuthorizationStatus {
        manager.authorizationStatus
    }
}
