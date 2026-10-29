import Combine
import CoreLocation
import Foundation
import MapKit
import SwiftUI

@MainActor
final class MapViewModel: ObservableObject {

    // MARK: - Route being edited

    @Published private(set) var mode: TravelMode = .drive
    @Published private(set) var waypoints: [Waypoint] = []
    @Published private(set) var plannedRoute: PlannedRoute?
    @Published private(set) var isRouting = false
    @Published var routeName = ""
    @Published var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @Published var notice: String?

    // MARK: - Options (remembered between launches)

    /// nil = follow the road's own speeds.
    @Published var speedCapMph: Double?
    @Published var followRoads: Bool {
        didSet {
            UserDefaults.standard.set(followRoads, forKey: UserDefaults.Keys.followRoads)
            if oldValue != followRoads { replan() }
        }
    }
    @Published var stopsEnabled: Bool {
        didSet { UserDefaults.standard.set(stopsEnabled, forKey: UserDefaults.Keys.stopsEnabled) }
    }
    @Published var wander: Bool {
        didSet {
            UserDefaults.standard.set(wander, forKey: UserDefaults.Keys.gpsWander)
            player.wanderEnabled = wander
        }
    }
    @Published var loop = false {
        didSet { player.loop = loop }
    }
    @Published var pingPong = false {
        didSet { player.pingPong = pingPong }
    }

    let player = RoutePlayer()

    private var routeTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init() {
        let defaults = UserDefaults.standard
        followRoads = defaults.object(forKey: UserDefaults.Keys.followRoads) as? Bool ?? true
        stopsEnabled = defaults.object(forKey: UserDefaults.Keys.stopsEnabled) as? Bool ?? true
        wander = defaults.object(forKey: UserDefaults.Keys.gpsWander) as? Bool ?? true
        player.wanderEnabled = wander

        // Re-publish player changes so views only need to watch this model.
        player.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Derived

    var isActive: Bool { player.state.isActive }

    var routePoints: [CLLocationCoordinate2D] {
        if let plannedRoute { return plannedRoute.points }
        return mode.isRoute ? waypoints.map(\.coordinate) : []
    }

    var routeLength: CLLocationDistance {
        RouteGeometry.totalDistance(routePoints)
    }

    var stopPoints: [CLLocationCoordinate2D] {
        guard let route = player.route, let plan = player.plan else { return [] }
        return plan.stops.map { route.position(at: $0.distance).coordinate }
    }

    var canStart: Bool {
        guard !isActive else { return false }
        return mode.isRoute ? waypoints.count >= 2 && !isRouting : !waypoints.isEmpty
    }

    var hint: String {
        if mode == .hold {
            return waypoints.isEmpty ? "Tap the map or search to pick a spot." : "Tap Teleport, or tap the map to move the pin."
        }
        switch waypoints.count {
        case 0: return "Tap the map or search to set the start."
        case 1: return "Now tap where you're going."
        default: return "Tap to add more stops along the way."
        }
    }

    // MARK: - Editing

    func setMode(_ newMode: TravelMode) {
        guard newMode != mode, !isActive else { return }
        mode = newMode
        if !newMode.isRoute, let last = waypoints.last {
            waypoints = [last]
        }
        replan()
    }

    func handleTap(_ coordinate: CLLocationCoordinate2D) {
        if mode == .hold {
            waypoints = [Waypoint(coordinate: coordinate, name: "Spot")]
            // Already teleported: move there now.
            if player.state == .holding {
                player.hold(at: coordinate)
            }
            return
        }
        guard !isActive else {
            notice = "Stop the route to edit it."
            return
        }
        waypoints.append(Waypoint(coordinate: coordinate))
        replan()
    }

    func addPlace(_ place: PlaceResult) {
        handleTap(place.coordinate)
        if let index = waypoints.indices.last {
            waypoints[index].name = place.name
        }
        cameraPosition = .camera(MapCamera(centerCoordinate: place.coordinate, distance: 2500))
    }

    func addMyLocation() {
        let manager = DeviceLocationManager.shared
        manager.requestAuthorizationIfNeeded()
        manager.startUpdating()
        guard let coordinate = manager.coordinate else {
            notice = "Waiting for your location. Try again in a second."
            return
        }
        if mode.isRoute, !isActive {
            waypoints.insert(Waypoint(coordinate: coordinate, name: "My location"), at: 0)
            replan()
        } else {
            handleTap(coordinate)
        }
        cameraPosition = .camera(MapCamera(centerCoordinate: coordinate, distance: 2500))
    }

    func removeWaypoint(_ id: UUID) {
        guard !isActive else { return }
        waypoints.removeAll { $0.id == id }
        replan()
    }

    func undoLast() {
        guard !isActive, !waypoints.isEmpty else { return }
        waypoints.removeLast()
        replan()
    }

    func reverse() {
        guard !isActive else { return }
        waypoints.reverse()
        replan()
    }

    func clear() {
        guard !isActive else { return }
        waypoints = []
        routeName = ""
        replan()
    }

    // MARK: - Routing

    func replan() {
        routeTask?.cancel()
        guard mode.isRoute, waypoints.count >= 2 else {
            plannedRoute = nil
            isRouting = false
            return
        }
        isRouting = true
        let coordinates = waypoints.map(\.coordinate)
        let mode = mode
        let followRoads = followRoads
        routeTask = Task {
            let route = await RoutePlanner.plan(coordinates, mode: mode, followRoads: followRoads)
            guard !Task.isCancelled else { return }
            plannedRoute = route
            isRouting = false
        }
    }

    // MARK: - Playback

    func start() {
        guard canStart else { return }
        if mode == .hold {
            guard let spot = waypoints.last else { return }
            player.hold(at: spot.coordinate)
            return
        }

        let planned = plannedRoute ?? RoutePlanner.straightLine(waypoints.map(\.coordinate))
        let polyline = Polyline(planned.points)
        let plan = MotionPlan.build(
            route: polyline,
            mode: mode,
            speedCap: speedCapMph.map { $0 * Units.mphToMps },
            segmentSpeeds: planned.segmentSpeeds,
            junctions: planned.junctions.map { polyline.distanceAlong(nearestTo: $0) },
            turns: planned.turns.map { polyline.distanceAlong(nearestTo: $0) },
            stopsEnabled: stopsEnabled
        )
        player.loop = loop
        player.pingPong = pingPong
        player.play(route: polyline, plan: plan)
    }

    func togglePause() {
        switch player.state {
        case .playing, .waiting: player.pause()
        case .paused, .finished: player.resume()
        default: break
        }
    }

    func stop() {
        player.stop()
    }

    // MARK: - Library

    func load(_ route: SavedRoute) {
        if isActive { player.stop() }
        mode = route.mode
        waypoints = route.waypoints
        routeName = route.name
        speedCapMph = route.speedCapMph
        followRoads = route.followRoads
        replan()
        frame(route.waypoints.map(\.coordinate))
    }

    func saveRoute() {
        guard !waypoints.isEmpty else { return }
        let name = routeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let route = SavedRoute(
            name: name.isEmpty ? defaultRouteName() : name,
            mode: mode,
            waypoints: waypoints,
            speedCapMph: speedCapMph,
            followRoads: followRoads
        )
        RouteStore.shared.save(route)
        notice = "Saved \"\(route.name)\"."
    }

    func importRoute(from url: URL) {
        do {
            let coordinates = try GPXImporter.parse(url: url)
            if isActive { player.stop() }
            if mode == .hold { mode = .drive }
            // A recorded track is already the path; don't re-route it.
            waypoints = coordinates.map { Waypoint(coordinate: $0) }
            routeName = url.deletingPathExtension().lastPathComponent
            plannedRoute = RoutePlanner.straightLine(coordinates)
            if coordinates.count <= 25 {
                replan()
            }
            frame(coordinates)
            notice = "Imported \(coordinates.count) points."
        } catch {
            notice = error.localizedDescription
        }
    }

    private func defaultRouteName() -> String {
        let miles = routeLength / Units.metersPerMile
        return "\(mode.displayName) \(String(format: "%.1f", miles)) mi"
    }

    private func frame(_ coordinates: [CLLocationCoordinate2D]) {
        guard !coordinates.isEmpty else { return }
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.01, (lats.max()! - lats.min()!) * 1.4),
            longitudeDelta: max(0.01, (lons.max()! - lons.min()!) * 1.4)
        )
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }
}
