import CoreLocation
import Foundation

// MARK: - Waypoint

struct Waypoint: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var latitude: Double
    var longitude: Double
    var name: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(coordinate: CLLocationCoordinate2D, name: String? = nil) {
        self.latitude  = coordinate.latitude
        self.longitude = coordinate.longitude
        self.name      = name
    }
}

// MARK: - SavedRoute

struct SavedRoute: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var mode: TravelMode
    var waypoints: [Waypoint]
    /// mph ceiling; nil means use the road's own speeds.
    var speedCapMph: Double?
    var followRoads: Bool = true
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var totalDistanceMeters: Double {
        RouteGeometry.totalDistance(waypoints.map(\.coordinate))
    }
}
