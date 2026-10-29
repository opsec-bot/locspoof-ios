import CoreLocation

// MARK: - GPS wander
//
// A phone that reports byte-identical coordinates for thirty seconds, or rides
// exactly on the road centreline, is obviously simulated. Real fixes wander by
// a few metres, and wander smoothly, because consecutive fixes share most of
// their error sources.
//
// So this is not independent noise per tick (that looks like TV static). It is
// an Ornstein-Uhlenbeck process, the standard model for correlated,
// mean-reverting drift:  dx = -(x/τ)dt + σ·√(2dt/τ)·dW
// Ported from locspoof's jitter.py.

final class GpsJitter {
    static let stillSigma = 3.0
    static let movingSigma = 1.5
    /// Speed at which wander has fully tightened to `movingSigma`.
    static let tightenSpeed = 1.5
    /// Correlation time in seconds.
    static let tau = 9.0

    private static let metersPerDegreeLatitude = 111_320.0

    private(set) var east: Double
    private(set) var north: Double
    private var rng: SeededRandom

    init(seed: UInt64? = nil) {
        rng = seed.map(SeededRandom.init(seed:)) ?? SeededRandom()
        // Start already displaced. Starting at zero would make the first fix
        // perfectly accurate, which no real receiver ever is.
        east = rng.gaussian() * Self.stillSigma
        north = rng.gaussian() * Self.stillSigma
    }

    var offsetMeters: Double { (east * east + north * north).squareRoot() }

    static func sigma(forSpeed speed: Double) -> Double {
        guard speed > 0 else { return stillSigma }
        let blend = min(1, speed / tightenSpeed)
        return stillSigma + (movingSigma - stillSigma) * blend
    }

    func advance(dt: TimeInterval, speed: Double) {
        guard dt > 0 else { return }
        // Cap the step: past τ the process has forgotten its history anyway.
        let step = min(dt, Self.tau)
        let decay = step / Self.tau
        let kick = Self.sigma(forSpeed: speed) * (2 * decay).squareRoot()
        east += -east * decay + kick * rng.gaussian()
        north += -north * decay + kick * rng.gaussian()
    }

    func apply(to point: CLLocationCoordinate2D, dt: TimeInterval, speed: Double) -> CLLocationCoordinate2D {
        advance(dt: dt, speed: speed)
        let cosLat = max(0.01, cos(point.latitude * .pi / 180))
        return CLLocationCoordinate2D(
            latitude: point.latitude + north / Self.metersPerDegreeLatitude,
            longitude: point.longitude + east / (Self.metersPerDegreeLatitude * cosLat)
        )
    }
}
