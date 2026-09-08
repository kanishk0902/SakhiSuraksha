//
//  GuardianMap.swift
//  Guardian
//
//  Reusable MapKit map that renders the Safety Corridor layers: routes, safer
//  route, safe places, incidents, CCTV placeholders, safety zones and mesh nodes.
//

import SwiftUI
import MapKit

struct GuardianMap: View {
    var routes: [[CLLocationCoordinate2D]] = []
    var saferRoute: [CLLocationCoordinate2D]? = nil
    var safePlaces: [SafePlace] = []
    var incidents: [Incident] = []
    var communityReports: [CommunityReport] = []
    var cctv: [CCTVEvent] = []
    var zones: [SafetyZone] = []
    var meshNodes: [CLLocationCoordinate2D] = []
    var destination: CLLocationCoordinate2D? = nil
    var showsUser: Bool = true
    /// When true, the camera frames the primary route's full extent (plus
    /// destination) on appear/route-change, like a turn-by-turn nav app
    /// showing the whole trip — instead of MapKit's default "just the user"
    /// framing, which is why a route could look like it wasn't really there.
    var fitsRouteOnAppear: Bool = false

    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $camera) {
            if showsUser {
                UserAnnotation()
            }

            // Safety zones as translucent circles.
            ForEach(zones) { zone in
                MapCircle(center: zone.center, radius: zone.radius)
                    .foregroundStyle((zone.score >= 70 ? GuardianTheme.safe : GuardianTheme.alert)
                        .opacity(0.12))
                    .stroke(zone.score >= 70 ? GuardianTheme.safe : GuardianTheme.alert,
                            lineWidth: 1)
            }

            // Routes.
            ForEach(Array(routes.enumerated()), id: \.offset) { index, route in
                MapPolyline(coordinates: route)
                    .stroke(index == 0 ? GuardianTheme.accent : Color.secondary.opacity(0.6),
                            style: StrokeStyle(lineWidth: index == 0 ? 6 : 4,
                                               lineCap: .round,
                                               dash: index == 0 ? [] : [6, 6]))
            }

            // Safer route highlighted in green.
            if let saferRoute {
                MapPolyline(coordinates: saferRoute)
                    .stroke(GuardianTheme.safe,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }

            // Destination.
            if let destination {
                Marker("Destination", systemImage: "flag.checkered", coordinate: destination)
                    .tint(GuardianTheme.accent)
            }

            // Safe places.
            ForEach(safePlaces) { place in
                Marker(place.name, systemImage: place.type.symbol, coordinate: place.coordinate)
                    .tint(place.type.tint)
            }

            // Incidents.
            ForEach(incidents) { incident in
                Annotation(incident.type.title, coordinate: incident.coordinate) {
                    Image(systemName: incident.type.symbol)
                        .font(.caption)
                        .padding(6)
                        .background(GuardianTheme.alert, in: Circle())
                        .foregroundStyle(.white)
                }
            }

            // Community safety reports (local-device only — see CommunityReport).
            ForEach(communityReports) { report in
                Annotation(report.reportType.title,
                          coordinate: CLLocationCoordinate2D(latitude: report.latitude, longitude: report.longitude)) {
                    Image(systemName: report.reportType.symbol)
                        .font(.caption)
                        .padding(6)
                        .background(GuardianTheme.caution, in: Circle())
                        .foregroundStyle(.white)
                }
            }

            // CCTV placeholders.
            ForEach(cctv) { cam in
                Annotation("CCTV", coordinate: cam.coordinate) {
                    Image(systemName: cam.isAnomaly ? "video.slash.fill" : "video.fill")
                        .font(.caption)
                        .padding(6)
                        .background(cam.isAnomaly ? GuardianTheme.alert : GuardianTheme.accent,
                                    in: Circle())
                        .foregroundStyle(.white)
                }
            }

            // Mesh nodes.
            ForEach(Array(meshNodes.enumerated()), id: \.offset) { _, node in
                Annotation("Mesh", coordinate: node) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.caption)
                        .padding(6)
                        .background(GuardianTheme.caution, in: Circle())
                        .foregroundStyle(.white)
                }
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .onAppear { fitRouteIfNeeded() }
        .onChange(of: routes.first?.count) { _, _ in fitRouteIfNeeded() }
    }

    private func fitRouteIfNeeded() {
        guard fitsRouteOnAppear else { return }
        var points = routes.first ?? []
        if let destination { points.append(destination) }
        guard points.count >= 2 else { return }

        var minLat = points[0].latitude, maxLat = points[0].latitude
        var minLon = points[0].longitude, maxLon = points[0].longitude
        for p in points {
            minLat = min(minLat, p.latitude); maxLat = max(maxLat, p.latitude)
            minLon = min(minLon, p.longitude); maxLon = max(maxLon, p.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        // Pad the span so the route isn't flush against the map edges.
        let span = MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.5, 0.006),
                                    longitudeDelta: max((maxLon - minLon) * 1.5, 0.006))
        withAnimation(.easeInOut(duration: 0.4)) {
            camera = .region(MKCoordinateRegion(center: center, span: span))
        }
    }
}
