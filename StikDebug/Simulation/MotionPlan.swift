import CoreLocation

// MARK: - Motion plan
//
// A constant-speed walk down a polyline is the loudest tell a simulated location
// has. Nothing real holds 30 mph for twenty minutes, takes a 90° corner without
// slowing, or crosses forty intersections without ever waiting.
//
// This turns a route into speed as a function of distance travelled, in four
// passes (ported from locspoof's motion.py):
//
// 1. A speed ceiling per sample, from road speeds when available.
// 2. Corner braking, from the turn angle at each vertex.
// 3. Stops at real junctions and turns, which pin the ceiling near zero.
// 4. A forward pass limiting acceleration and a backward pass limiting braking,
//    so the phone eases away from a stop and brakes into it.

struct PlannedStop: Equatable {
    let distance: CLLocationDistance
    let dwell: TimeInterval
    let reason: String
}

struct MotionPlan {
    /// Sampling resolution along the route.
    static let sampleStep: CLLocationDistance = 2.0
    /// Caps memory on very long routes by coarsening instead of growing.
    static let maxSamples = 40_000
    /// Speed floor at a stop. Not zero: the player advances by v·dt, so zero
    /// would mean never reaching the point it is braking for. The real
    /// standstill is the dwell timer, during which position does not change.
    static let stopFloor: CLLocationSpeed = 0.6

    let step: CLLocationDistance
    let speeds: [CLLocationSpeed]
    let stops: [PlannedStop]
    let length: CLLocationDistance

    /// Speed at a distance along the route, linearly interpolated.
    func speed(at distance: CLLocationDistance) -> CLLocationSpeed {
        guard let first = speeds.first, let last = speeds.last else { return 0 }
        if distance <= 0 { return first }
        let index = distance / step
        let low = Int(index)
        if low >= speeds.count - 1 { return last }
        let fraction = index - Double(low)
        return speeds[low] * (1 - fraction) + speeds[low + 1] * fraction
    }

    /// Time to cover the whole route, including waiting at stops.
    var estimatedDuration: TimeInterval {
        var total = stops.reduce(0) { $0 + $1.dwell }
        for v in speeds.dropLast() {
            total += step / max(v, 0.35)
        }
        return total
    }

    /// Time left from `distance` onward, counting only stops still ahead.
    func remainingDuration(from distance: CLLocationDistance) -> TimeInterval {
        let start = max(0, min(Int(distance / step), speeds.count - 1))
        var total = stops.filter { $0.distance > distance }.reduce(0) { $0 + $1.dwell }
        if start < speeds.count - 1 {
            for v in speeds[start..<(speeds.count - 1)] {
                total += step / max(v, 0.35)
            }
        }
        return total
    }

    // MARK: - Build

    /// - Parameters:
    ///   - speedCap: user ceiling in m/s. A ceiling, not an override: a 65 mph
    ///     setting still crawls through a corner, it just never exceeds 65.
    ///   - segmentSpeeds: road speed per route segment in m/s, nil where unknown.
    ///   - junctions, turns: distances along the route.
    static func build(
        route: Polyline,
        mode: TravelMode,
        speedCap: CLLocationSpeed?,
        segmentSpeeds: [Double?] = [],
        junctions: [CLLocationDistance] = [],
        turns: [CLLocationDistance] = [],
        stopsEnabled: Bool = true,
        seed: UInt64? = nil
    ) -> MotionPlan {
        let params = mode.params
        var rng = seed.map(SeededRandom.init(seed:)) ?? SeededRandom()

        let length = route.length
        var step = sampleStep
        if length / step > Double(maxSamples) {
            step = length / Double(maxSamples)
        }
        let count = max(2, Int(length / step) + 1)

        // Pass 1: ceiling from road speeds.
        let hasRoadSpeeds = segmentSpeeds.contains { ($0 ?? 0) > 0.2 }
        var ceiling = [CLLocationSpeed](repeating: 0, count: count)
        for i in 0..<count {
            var base = params.defaultSpeed
            if hasRoadSpeeds, let road = roadSpeed(route: route, segmentSpeeds: segmentSpeeds, at: Double(i) * step) {
                base = road
            }
            if let speedCap {
                base = hasRoadSpeeds ? min(base, speedCap) : speedCap
            }
            ceiling[i] = min(base, params.maxSpeed)
        }

        // Pass 2: corner braking, applied over a short window so the corner has
        // width and the smoothing passes have something to brake into.
        if route.points.count >= 3 {
            for index in 1..<(route.points.count - 1) {
                let before = route.cumulative[index] - route.cumulative[index - 1]
                let after = route.cumulative[index + 1] - route.cumulative[index]
                // Duplicate points have no bearing; skip them rather than invent a corner.
                guard before > 0.5, after > 0.5 else { continue }
                let angle = RouteGeometry.turnAngle(at: index, coords: route.points)
                let cap = params.cornerCap(for: angle)
                guard cap.isFinite else { continue }
                for i in window(centre: route.cumulative[index], halfWidth: 6, step: step, count: count) {
                    ceiling[i] = min(ceiling[i], cap)
                }
            }
        }

        // Pass 3: stops at junctions and turns.
        var stops: [PlannedStop] = []
        if stopsEnabled {
            var candidates: [(distance: Double, reason: String, chance: Double)] = []
            candidates += junctions.map { (distance: $0, reason: "junction", chance: params.junctionStopChance) }
            candidates += turns.map { (distance: $0, reason: "turn", chance: params.turnStopChance) }
            candidates.sort { $0.distance < $1.distance }

            var lastStop = -Double.greatestFiniteMagnitude
            for candidate in candidates {
                // Never stop twice within 40 m, or right at either end.
                if candidate.distance - lastStop < 40 { continue }
                if candidate.distance < 15 || candidate.distance > length - 15 { continue }
                if rng.unit() > candidate.chance { continue }
                let dwell = rng.uniform(params.stopDwell)
                stops.append(PlannedStop(distance: candidate.distance, dwell: dwell, reason: candidate.reason))
                lastStop = candidate.distance
                for i in window(centre: candidate.distance, halfWidth: 1.5, step: step, count: count) {
                    ceiling[i] = min(ceiling[i], stopFloor)
                }
            }
        }

        // A journey starts from a standstill and ends at one.
        ceiling[0] = min(ceiling[0], stopFloor)
        ceiling[count - 1] = min(ceiling[count - 1], stopFloor)

        // Pass 4: make it physically reachable.
        let speeds = limitAcceleration(ceiling, step: step, accel: params.accel, decel: params.decel)
        return MotionPlan(step: step, speeds: speeds, stops: stops, length: length)
    }

    /// Two sweeps over v² = u² + 2as. Forward limits how fast speed may rise,
    /// backward limits how late braking may start.
    static func limitAcceleration(
        _ ceiling: [CLLocationSpeed],
        step: Double,
        accel: Double,
        decel: Double
    ) -> [CLLocationSpeed] {
        var out = ceiling
        guard out.count > 1 else { return out }
        for i in 1..<out.count {
            out[i] = min(out[i], (out[i - 1] * out[i - 1] + 2 * accel * step).squareRoot())
        }
        for i in stride(from: out.count - 2, through: 0, by: -1) {
            out[i] = min(out[i], (out[i + 1] * out[i + 1] + 2 * decel * step).squareRoot())
        }
        return out
    }

    private static func window(centre: Double, halfWidth: Double, step: Double, count: Int) -> ClosedRange<Int> {
        let lo = min(count - 1, max(0, Int((centre - halfWidth) / step)))
        let hi = min(count - 1, Int((centre + halfWidth) / step))
        return lo...max(lo, hi)
    }

    private static func roadSpeed(route: Polyline, segmentSpeeds: [Double?], at distance: Double) -> Double? {
        let cumulative = route.cumulative
        guard cumulative.count >= 2 else { return nil }
        var lo = 0
        var hi = cumulative.count - 1
        while lo < hi - 1 {
            let mid = (lo + hi) / 2
            if cumulative[mid] <= distance { lo = mid } else { hi = mid }
        }
        guard lo < segmentSpeeds.count, let value = segmentSpeeds[lo], value > 0.2 else { return nil }
        return value
    }
}
