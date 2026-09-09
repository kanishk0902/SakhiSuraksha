//
//  LocationService.swift
//  Guardian
//

import Foundation
import CoreLocation
import Observation

@Observable
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {

    private(set) var currentLocation: CLLocation?
    private(set) var heading: CLLocationDirection = 0
    private(set) var headingAccuracy: CLLocationDirection = -1
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var isSimulated: Bool = false
    private(set) var lastUpdate: Date?

    // MARK: Travel mode auto-detection
    // Smoothed over the last few readings so a single instant speed spike
    // (e.g. a driver stopped at a red light briefly reading near 0 km/h)
    // doesn't cause a misclassification. Not persisted or exposed as a
    // safety signal elsewhere — purely a UI convenience for pre-selecting a
    // travel mode in Safe Route search.
    private(set) var detectedMode: TravelMode = .walking
    private var recentSpeedsKph: [Double] = []
    private let speedHistoryLimit = 5

    static let fallbackCoordinate = CLLocationCoordinate2D(latitude: 28.6315, longitude: 77.2167)

    /// Fired when authorization transitions to "Always" — the "Always" grant
    /// is asynchronous (the user sees a system prompt), so callers that asked
    /// for it can't just re-check the status right after requesting it; this
    /// tells AppModel when it's safe to actually switch on background updates.
    var onAuthorizedAlways: (() -> Void)?

    private let manager = CLLocationManager()
    private var isMonitoring = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        authorizationStatus = manager.authorizationStatus
    }

    var coordinate: CLLocationCoordinate2D {
        currentLocation?.coordinate ?? Self.fallbackCoordinate
    }

    var hasValidCoordinate: Bool {
        true // always valid — uses fallback if no GPS fix yet
    }

    var hasPermission: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    /// Requests "Always" authorization — needed so an active journey keeps
    /// monitoring location (and can raise a deviation/emergency alert) after
    /// the app is backgrounded or the screen locks. Only worth prompting for
    /// once the user has already granted when-in-use, otherwise iOS ignores
    /// the request.
    func requestAlwaysPermission() {
        guard authorizationStatus == .authorizedWhenInUse else { return }
        manager.requestAlwaysAuthorization()
    }

    func startContinuous() {
        if !hasPermission {
            manager.requestWhenInUseAuthorization()
            return
        }
        guard !isMonitoring else { return }
        isMonitoring = true
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    func stopContinuous() {
        guard isMonitoring else { return }
        isMonitoring = false
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        setBackgroundTracking(false)
    }

    /// Enables/disables background location delivery. Called only while a
    /// journey is active so Guardian doesn't run background GPS the rest of
    /// the time — matches the "Always" permission's stated purpose and
    /// avoids draining battery outside of a monitored trip.
    func setBackgroundTracking(_ enabled: Bool) {
        guard authorizationStatus == .authorizedAlways else {
            manager.allowsBackgroundLocationUpdates = false
            manager.pausesLocationUpdatesAutomatically = true
            return
        }
        manager.allowsBackgroundLocationUpdates = enabled
        manager.pausesLocationUpdatesAutomatically = !enabled
        manager.showsBackgroundLocationIndicator = enabled
    }

    func startHeading() {
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    func stopHeading() {
        manager.stopUpdatingHeading()
    }

    func setSimulated(_ coordinate: CLLocationCoordinate2D) {
        isSimulated = true
        currentLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        lastUpdate = .now
    }

    func nudgeSimulated(latMeters: Double, lonMeters: Double) {
        setSimulated(coordinate.offset(latMeters: latMeters, lonMeters: lonMeters))
    }

    func bearing(to target: CLLocationCoordinate2D) -> CLLocationDirection {
        Self.bearing(from: coordinate, to: target)
    }

    /// Direction of travel for a navigation arrow/camera. GPS course
    /// (direction of actual movement) is far more reliable while
    /// walking/driving than the magnetometer heading, which reflects which
    /// way the phone is pointed, not which way the user is going — so prefer
    /// course when it's valid, falling back to compass heading, then bearing
    /// toward a destination if one is given.
    func navigationHeading(fallbackBearingTo destination: CLLocationCoordinate2D? = nil) -> CLLocationDirection? {
        if let loc = currentLocation, loc.course >= 0 {
            return loc.course
        }
        if headingAccuracy >= 0 {
            return heading
        }
        if let destination {
            return bearing(to: destination)
        }
        return nil
    }

    static func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDirection {
        let lat1 = from.latitude * .pi / 180
        let lon1 = from.longitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let lon2 = to.longitude * .pi / 180
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.isMonitoring = false // reset so startContinuous proceeds
                self.startContinuous()
                if status == .authorizedAlways {
                    self.onAuthorizedAlways?()
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last, loc.horizontalAccuracy >= 0 else { return }
        Task { @MainActor in
            self.currentLocation = loc
            self.isSimulated = false
            self.lastUpdate = .now
            self.recordSpeed(loc.speed)
        }
    }

    private func recordSpeed(_ speedMetersPerSecond: CLLocationSpeed) {
        guard speedMetersPerSecond >= 0 else { return } // negative = invalid reading
        let kph = speedMetersPerSecond * 3.6
        recentSpeedsKph.append(kph)
        if recentSpeedsKph.count > speedHistoryLimit {
            recentSpeedsKph.removeFirst(recentSpeedsKph.count - speedHistoryLimit)
        }
        let smoothed = recentSpeedsKph.reduce(0, +) / Double(recentSpeedsKph.count)
        detectedMode = Self.classifyMode(smoothedKph: smoothed)
    }

    static func classifyMode(smoothedKph: Double) -> TravelMode {
        if smoothedKph < 6 { return .walking }
        if smoothedKph < 25 { return .cycling }
        return .driving
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let h = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        let a = newHeading.headingAccuracy
        Task { @MainActor in
            self.heading = h
            self.headingAccuracy = a
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // non-fatal
    }
}
