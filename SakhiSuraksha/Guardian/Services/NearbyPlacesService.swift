//
//  NearbyPlacesService.swift
//  Guardian
//
//  Reusable MapKit-backed nearby place search. All features (Period Emergency,
//  Medical SOS, Safe Havens, I Need Help) call this single service rather than
//  duplicating search logic.
//

import Foundation
import MapKit
import CoreLocation
import Observation

// MARK: - Result type

struct NearbyPlace: Identifiable {
    let id = UUID()
    var name: String
    var address: String
    var coordinate: CLLocationCoordinate2D
    var phone: String?
    var distance: CLLocationDistance
    var isOpen: Bool?           // nil = unknown
    var category: String

    var distanceText: String {
        distance < 1000
            ? "\(Int(distance)) m"
            : String(format: "%.1f km", distance / 1000)
    }
}

// MARK: - Query type

enum NearbyPlaceQuery {
    case pharmacy
    case hospital
    case restroom
    case policeStation
    case cafe
    case petrolPump
    case custom(String)

    var searchTerm: String {
        switch self {
        case .pharmacy:      return "pharmacy"
        case .hospital:      return "hospital"
        case .restroom:      return "public toilet"
        case .policeStation: return "police station"
        case .cafe:          return "cafe"
        case .petrolPump:    return "petrol pump"
        case .custom(let q): return q
        }
    }

    var displayName: String {
        switch self {
        case .pharmacy:      return "Pharmacy"
        case .hospital:      return "Hospital"
        case .restroom:      return "Washroom"
        case .policeStation: return "Police Station"
        case .cafe:          return "Café"
        case .petrolPump:    return "Petrol Pump"
        case .custom(let q): return q.capitalized
        }
    }
}

// MARK: - Service

@Observable
@MainActor
final class NearbyPlacesService {

    private(set) var results: [NearbyPlace] = []
    private(set) var isSearching = false
    private(set) var errorMessage: String?
    private(set) var lastQuery: NearbyPlaceQuery?
    private(set) var searchRadiusMeters: Double = 1500
    private(set) var lastCoordinate: CLLocationCoordinate2D?

    func search(for query: NearbyPlaceQuery,
                near coordinate: CLLocationCoordinate2D,
                radiusMeters: Double = 1500) async {
        isSearching = true
        errorMessage = nil
        lastQuery = query
        lastCoordinate = coordinate
        searchRadiusMeters = radiusMeters
        results = []

        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: radiusMeters,
            longitudinalMeters: radiusMeters)

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query.searchTerm
        request.region = region
        request.resultTypes = .pointOfInterest

        do {
            let response = try await MKLocalSearch(request: request).start()
            let userLoc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            results = response.mapItems.prefix(10).compactMap { item -> NearbyPlace? in
                guard let name = item.name else { return nil }
                let coord = item.placemark.coordinate
                let dist = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                    .distance(from: userLoc)
                let address = [
                    item.placemark.thoroughfare,
                    item.placemark.locality
                ].compactMap { $0 }.joined(separator: ", ")
                return NearbyPlace(
                    name: name,
                    address: address,
                    coordinate: coord,
                    phone: item.phoneNumber,
                    distance: dist,
                    isOpen: nil,
                    category: query.displayName)
            }
            .sorted { $0.distance < $1.distance }

            if results.isEmpty {
                errorMessage = "No \(query.displayName.lowercased()) found within \(Int(radiusMeters / 1000)) km."
            }
        } catch {
            errorMessage = "Search failed. Check your internet connection."
        }

        isSearching = false
    }

    func searchWider() async {
        guard let query = lastQuery, let coordinate = lastCoordinate else { return }
        await search(for: query,
                     near: coordinate,
                     radiusMeters: searchRadiusMeters * 3)
    }

    func openInMaps(_ place: NearbyPlace) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
        item.name = place.name
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ])
    }

    func call(_ place: NearbyPlace) {
        guard let phone = place.phone,
              let url = URL(string: "tel://\(phone.filter { $0.isNumber || $0 == "+" })") else { return }
        UIApplication.shared.open(url)
    }
}
