import CoreLocation
import Foundation
import MapKit

// MARK: - Planned route

struct PlannedRoute {
    var points: [CLLocationCoordinate2D]
    /// Road speed per geometry segment (m/s), nil where unknown.
    var segmentSpeeds: [Double?]
    var junctions: [CLLocationCoordinate2D]
    var turns: [CLLocationCoordinate2D]
    /// Which engine answered: "OSRM", "Apple Maps" or "Straight line".
    var source: String
    /// Real lights and signs from OSM, filled in after the route arrives.
    /// nil until then, or when Overpass could not be reached.
    var controls: [TrafficControl]? = nil
}

struct PlaceResult: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let subtitle: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - RoutePlanner
//
// Road routing goes to public OSRM servers first, because OSRM also returns
// per-segment road speeds, junctions and turns, which feed the motion plan
// (real stops at real intersections). Apple Maps is the fallback, and a
// straight line is the last resort. Ported from locspoof's routing.py.

enum RoutePlanner {
    private static let userAgent = "locspoof-ios/1.0 (personal location simulator)"

    private static func osrmEndpoints(for mode: TravelMode) -> [String] {
        switch mode {
        case .drive, .hold:
            return [
                "https://router.project-osrm.org/route/v1/driving/",
                "https://routing.openstreetmap.de/routed-car/route/v1/driving/"
            ]
        case .bike:
            return [
                "https://routing.openstreetmap.de/routed-bike/route/v1/driving/",
                "https://router.project-osrm.org/route/v1/driving/"
            ]
        case .walk:
            return [
                "https://routing.openstreetmap.de/routed-foot/route/v1/driving/",
                "https://router.project-osrm.org/route/v1/driving/"
            ]
        }
    }

    /// Manoeuvres that involve actually turning. "new name" and "continue" are
    /// just the road changing name underneath you.
    // Only manoeuvres where a car can actually come to a halt. Forks, merges and
    // ramps happen at speed, so counting them put full stops on the highway.
    private static let turnManeuvers: Set<String> = [
        "turn", "end of road", "roundabout", "rotary", "roundabout turn"
    ]

    static func straightLine(_ waypoints: [CLLocationCoordinate2D]) -> PlannedRoute {
        PlannedRoute(points: waypoints, segmentSpeeds: [], junctions: [], turns: [], source: "Straight line")
    }

    static func plan(_ waypoints: [CLLocationCoordinate2D], mode: TravelMode, followRoads: Bool) async -> PlannedRoute {
        guard waypoints.count >= 2, followRoads else {
            return straightLine(waypoints)
        }
        if let route = await osrm(waypoints, mode: mode) {
            return route
        }
        if let route = await appleMaps(waypoints, mode: mode) {
            return route
        }
        return straightLine(waypoints)
    }

    // MARK: - OSRM

    private static func osrm(_ waypoints: [CLLocationCoordinate2D], mode: TravelMode) async -> PlannedRoute? {
        let coords = waypoints
            .map { String(format: "%.6f,%.6f", $0.longitude, $0.latitude) }
            .joined(separator: ";")
        let query = "?overview=full&geometries=geojson&continue_straight=false&steps=true&annotations=true"

        for base in osrmEndpoints(for: mode) {
            guard let url = URL(string: base + coords + query) else { continue }
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["code"] as? String == "Ok",
                  let route = (json["routes"] as? [[String: Any]])?.first,
                  let geometry = route["geometry"] as? [String: Any],
                  let coordinates = geometry["coordinates"] as? [[Double]] else {
                LogManager.shared.addInfoLog("OSRM \(base) gave no route")
                continue
            }

            // GeoJSON is [lon, lat].
            let points = coordinates.compactMap { pair -> CLLocationCoordinate2D? in
                guard pair.count >= 2 else { return nil }
                return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
            }
            guard points.count >= 2 else { continue }

            var speeds: [Double?] = []
            var junctions: [CLLocationCoordinate2D] = []
            var turns: [CLLocationCoordinate2D] = []

            for leg in route["legs"] as? [[String: Any]] ?? [] {
                if let annotation = leg["annotation"] as? [String: Any],
                   let values = annotation["speed"] as? [Any] {
                    speeds += values.map { ($0 as? NSNumber)?.doubleValue }
                }
                for step in leg["steps"] as? [[String: Any]] ?? [] {
                    if let maneuver = step["maneuver"] as? [String: Any],
                       let type = maneuver["type"] as? String,
                       turnManeuvers.contains(type),
                       let location = maneuver["location"] as? [Double], location.count >= 2 {
                        turns.append(CLLocationCoordinate2D(latitude: location[1], longitude: location[0]))
                    }
                    for intersection in step["intersections"] as? [[String: Any]] ?? [] {
                        // Two bearings is the road bending; three or more is a real junction.
                        guard (intersection["bearings"] as? [Any])?.count ?? 0 >= 3,
                              let location = intersection["location"] as? [Double], location.count >= 2 else {
                            continue
                        }
                        junctions.append(CLLocationCoordinate2D(latitude: location[1], longitude: location[0]))
                    }
                }
            }

            return PlannedRoute(points: points, segmentSpeeds: speeds, junctions: junctions, turns: turns, source: "OSRM")
        }
        return nil
    }

    // MARK: - Apple Maps fallback

    private static func appleMaps(_ waypoints: [CLLocationCoordinate2D], mode: TravelMode) async -> PlannedRoute? {
        var points: [CLLocationCoordinate2D] = []
        for (start, end) in zip(waypoints, waypoints.dropFirst()) {
            let request = MKDirections.Request()
            request.source = mapItem(start)
            request.destination = mapItem(end)
            request.transportType = mode == .drive ? .automobile : .walking
            guard let response = try? await MKDirections(request: request).calculate(),
                  let route = response.routes.first else {
                return nil
            }
            var leg = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: route.polyline.pointCount)
            route.polyline.getCoordinates(&leg, range: NSRange(location: 0, length: route.polyline.pointCount))
            if !points.isEmpty { leg = Array(leg.dropFirst()) }
            points += leg
        }
        guard points.count >= 2 else { return nil }
        return PlannedRoute(points: points, segmentSpeeds: [], junctions: [], turns: [], source: "Apple Maps")
    }

    private static func mapItem(_ coordinate: CLLocationCoordinate2D) -> MKMapItem {
        if #available(iOS 26.0, *) {
            return MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), address: nil)
        } else {
            return MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        }
    }

    // MARK: - Place search

    static func search(_ query: String, near center: CLLocationCoordinate2D?) async -> [PlaceResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if let coordinate = parseCoordinate(trimmed) {
            return [PlaceResult(
                name: String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude),
                subtitle: "Coordinates",
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )]
        }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        if let center {
            request.region = MKCoordinateRegion(center: center, latitudinalMeters: 50_000, longitudinalMeters: 50_000)
        }
        if let response = try? await MKLocalSearch(request: request).start(), !response.mapItems.isEmpty {
            return response.mapItems.prefix(12).map { item in
                let coordinate = item.placemark.coordinate
                return PlaceResult(
                    name: item.name ?? "Unnamed place",
                    subtitle: item.placemark.title ?? "",
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
            }
        }
        return await nominatim(trimmed)
    }

    /// "32.95, -96.89" style input goes straight to a point.
    static func parseCoordinate(_ text: String) -> CLLocationCoordinate2D? {
        let parts = text
            .replacingOccurrences(of: " ", with: ",")
            .split(separator: ",")
            .compactMap { Double($0) }
        guard parts.count == 2,
              (-90...90).contains(parts[0]),
              (-180...180).contains(parts[1]) else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: parts[0], longitude: parts[1])
    }

    private static func nominatim(_ query: String) async -> [PlaceResult] {
        var components = URLComponents(string: "https://nominatim.openstreetmap.org/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "jsonv2"),
            URLQueryItem(name: "limit", value: "8")
        ]
        guard let url = components?.url else { return [] }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return rows.compactMap { row in
            guard let lat = Double(row["lat"] as? String ?? ""),
                  let lon = Double(row["lon"] as? String ?? "") else { return nil }
            let full = row["display_name"] as? String ?? ""
            let name = full.components(separatedBy: ",").first ?? full
            return PlaceResult(name: name, subtitle: full, latitude: lat, longitude: lon)
        }
    }
}
