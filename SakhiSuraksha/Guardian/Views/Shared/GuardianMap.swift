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
    /// Per-route override colours (green/yellow/red by safety score). When set,
    /// routes[i] is drawn with routeColors[i]; unmatched indices fall back to
    /// the default accent/gray scheme. `saferRoute` is ignored when this is set.
    var routeColors: [Color]? = nil
    var safePlaces: [SafePlace] = []
    var incidents: [Incident] = []
    var communityReports: [CommunityReport] = []
    var cctv: [CCTVEvent] = []
    var zones: [SafetyZone] = []
    var meshNodes: [CLLocationCoordinate2D] = []
    /// Journey checkpoints — displayed as numbered refuge-point pins distinct
    /// from the general safe-place markers.
    var checkpoints: [Checkpoint] = []
    var destination: CLLocationCoordinate2D? = nil
    var showsUser: Bool = true
    /// The user's current position and heading, drawn as a rotated navigation
    /// arrow (like Google/Apple Maps turn-by-turn) instead of the default
    /// blue dot when both are available. Falls back to `UserAnnotation()`
    /// when nil so non-navigation screens are unaffected.
    var userPosition: CLLocationCoordinate2D? = nil
    var userHeading: CLLocationDirection? = nil
    /// When true, only the route/destination/checkpoints/user layers are
    /// drawn — safe places, incidents, CCTV, zones, mesh and community
    /// reports are hidden so the live navigation map stays legible instead
    /// of cluttered with every overlay at once.
    var minimalOverlays: Bool = false
    /// When true, the camera frames the primary route's full extent (plus
    /// destination) on appear/route-change, like a turn-by-turn nav app
    /// showing the whole trip — instead of MapKit's default "just the user"
    /// framing, which is why a route could look like it wasn't really there.
    var fitsRouteOnAppear: Bool = false
    /// When true (with userPosition available), the camera continuously
    /// stays centered on the user — active turn-by-turn "follow me" mode,
    /// as opposed to the one-shot `fitsRouteOnAppear` framing. Ignored
    /// while fitsRouteOnAppear's one-shot fit hasn't happened yet on a
    /// brand-new route, so the initial framing still shows the whole trip.
    var followsUser: Bool = false
    /// When true (and followsUser), the camera rotates so the direction of
    /// travel is always "up" (heading-up navigation); when false, north
    /// stays up while still centering on the user.
    var headingUp: Bool = false
    /// Called when the user manually pans/zooms away from follow mode. This
    /// view does not own `followsUser` — the caller does — so it only
    /// reports the interaction and lets the caller decide (e.g. flip its own
    /// state so a "Recenter" button reappears), matching this view's existing
    /// stateless-from-the-outside design.
    var onUserPanned: (() -> Void)? = nil

    @State private var camera: MapCameraPosition = .automatic
    /// Guards against `onMapCameraChange` mistaking our own follow-driven
    /// camera writes for a user gesture — set immediately around each
    /// programmatic update, cleared on the next camera-change callback.
    @State private var isProgrammaticCameraUpdate = false

    var body: some View {
        Map(position: $camera) {
            if let userPosition, let userHeading {
                Annotation("", coordinate: userPosition, anchor: .center) {
                    NavigationArrow(heading: userHeading)
                }
            } else if showsUser {
                UserAnnotation()
            }

            // Safety zones as translucent circles.
            ForEach(minimalOverlays ? [] : zones) { zone in
                MapCircle(center: zone.center, radius: zone.radius)
                    .foregroundStyle((zone.score >= 70 ? GuardianTheme.safe : GuardianTheme.alert)
                        .opacity(0.12))
                    .stroke(zone.score >= 70 ? GuardianTheme.safe : GuardianTheme.alert,
                            lineWidth: 1)
            }

            // Routes — coloured by safety tier when routeColors is provided,
            // otherwise accent for primary + dashed gray for alternates.
            // Never truncate to one route when routeColors is set — the whole
            // point of that mode is showing every route's safety tier
            // (green/yellow/red) side by side, so minimalOverlays only trims
            // the unrelated clutter layers, not the routes themselves.
            ForEach(Array((minimalOverlays && routeColors == nil ? Array(routes.prefix(1)) : routes).enumerated()), id: \.offset) { index, route in
                let color: Color = {
                    if let rc = routeColors, index < rc.count { return rc[index] }
                    return index == 0 ? GuardianTheme.accent : Color.secondary.opacity(0.6)
                }()
                let dash: [CGFloat] = (routeColors == nil && index != 0) ? [6, 6] : []
                MapPolyline(coordinates: route)
                    .stroke(color,
                            style: StrokeStyle(lineWidth: index == 0 ? 6 : 4,
                                               lineCap: .round,
                                               dash: dash))
            }

            // Safer route highlighted in green (used when routeColors is nil).
            if routeColors == nil, let saferRoute {
                MapPolyline(coordinates: saferRoute)
                    .stroke(GuardianTheme.safe,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }

            // Destination.
            if let destination {
                Marker("Destination", systemImage: "flag.checkered", coordinate: destination)
                    .tint(GuardianTheme.accent)
            }

            // Journey checkpoints — numbered refuge pins (police, hospital, etc.)
            ForEach(Array(checkpoints.enumerated()), id: \.offset) { index, cp in
                Annotation(cp.name, coordinate: cp.coordinate) {
                    ZStack {
                        Circle()
                            .fill(cp.reached ? GuardianTheme.safe : (cp.safePlaceType?.tint ?? GuardianTheme.accent))
                            .frame(width: 28, height: 28)
                            .shadow(radius: 3)
                        if cp.reached {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Text("\(index + 1)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
            }

            // Safe places.
            ForEach(safePlaces) { place in
                Marker(place.name, systemImage: place.type.symbol, coordinate: place.coordinate)
                    .tint(place.type.tint)
            }

            // Incidents.
            ForEach(minimalOverlays ? [] : incidents) { incident in
                Annotation(incident.type.title, coordinate: incident.coordinate) {
                    Image(systemName: incident.type.symbol)
                        .font(.caption)
                        .padding(6)
                        .background(GuardianTheme.alert, in: Circle())
                        .foregroundStyle(.white)
                }
            }

            // Community safety reports (local-device only — see CommunityReport).
            ForEach(minimalOverlays ? [] : communityReports) { report in
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
            ForEach(minimalOverlays ? [] : cctv) { cam in
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
            ForEach(Array((minimalOverlays ? [] : meshNodes).enumerated()), id: \.offset) { _, node in
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
        // CLLocationCoordinate2D isn't Equatable, so observe its scalar
        // components (still cheap, still precise) rather than the struct
        // itself — same idiom as the existing `routes.first?.count` trigger.
        .onChange(of: userPosition?.latitude) { _, _ in updateFollowCamera(position: userPosition) }
        .onChange(of: userPosition?.longitude) { _, _ in updateFollowCamera(position: userPosition) }
        .onChange(of: userHeading) { _, _ in
            if headingUp { updateFollowCamera(position: userPosition) }
        }
        .onChange(of: followsUser) { _, isFollowing in
            if isFollowing { updateFollowCamera(position: userPosition) }
        }
        .onMapCameraChange(frequency: .onEnd) { _ in
            if isProgrammaticCameraUpdate {
                isProgrammaticCameraUpdate = false
            } else if followsUser {
                onUserPanned?()
            }
        }
    }

    /// Recenters the camera on the user for active-navigation "follow me"
    /// mode. A fixed nav-style distance/pitch keeps the upcoming route
    /// visible without the map feeling zoomed out; linear animation matches
    /// the ~1/sec GPS update cadence so consecutive updates read as smooth
    /// continuous motion rather than settle-then-jump.
    private func updateFollowCamera(position: CLLocationCoordinate2D?) {
        guard followsUser, let position else { return }
        let heading = headingUp ? (userHeading ?? 0) : 0
        let pitch: Double = headingUp ? 60 : 0
        isProgrammaticCameraUpdate = true
        withAnimation(.linear(duration: 0.9)) {
            camera = .camera(MapCamera(centerCoordinate: position, distance: 400,
                                       heading: heading, pitch: pitch))
        }
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

/// A rotated triangular "puck" pointing in the direction of travel, matching
/// the turn-by-turn navigation marker used by Google/Apple Maps — clearer
/// than the plain blue dot for showing which way the user is heading.
struct NavigationArrow: View {
    var heading: CLLocationDirection

    var body: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 34, height: 34)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            TriangleArrow()
                .fill(GuardianTheme.accent)
                .frame(width: 18, height: 18)
                .rotationEffect(.degrees(heading))
        }
        .animation(.easeInOut(duration: 0.25), value: heading)
    }
}

private struct TriangleArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY * 0.72))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
