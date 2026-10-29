import CoreLocation

/// A route as a list of points plus the running distance to each one.
struct Polyline {
    let points: [CLLocationCoordinate2D]
    let cumulative: [CLLocationDistance]

    init(_ points: [CLLocationCoordinate2D]) {
        self.points = points
        self.cumulative = RouteGeometry.cumulativeDistances(points)
    }

    var length: CLLocationDistance { cumulative.last ?? 0 }
    var isEmpty: Bool { points.isEmpty }

    func position(at distance: CLLocationDistance) -> (coordinate: CLLocationCoordinate2D, bearing: CLLocationDirection) {
        RouteGeometry.position(at: distance, coords: points, cumulative: cumulative)
    }

    /// Distance along the route of the vertex closest to `target`.
    func distanceAlong(nearestTo target: CLLocationCoordinate2D) -> CLLocationDistance {
        var best = (distance: 0.0, gap: CLLocationDistance.greatestFiniteMagnitude)
        for (index, point) in points.enumerated() {
            let gap = RouteGeometry.distance(from: point, to: target)
            if gap < best.gap {
                best = (cumulative[index], gap)
            }
        }
        return best.distance
    }
}
