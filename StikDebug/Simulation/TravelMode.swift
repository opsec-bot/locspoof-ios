import CoreLocation

// MARK: - Travel mode

enum TravelMode: String, Codable, CaseIterable, Identifiable {
    case drive
    case bike
    case walk
    /// Sit at one point. No route, just a held location, exactly on the spot.
    case hold

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .drive: return "Drive"
        case .bike:  return "Bike"
        case .walk:  return "Walk"
        case .hold:  return "Teleport"
        }
    }

    var systemImage: String {
        switch self {
        case .drive: return "car.fill"
        case .bike:  return "bicycle"
        case .walk:  return "figure.walk"
        case .hold:  return "mappin.circle.fill"
        }
    }

    var isRoute: Bool { self != .hold }

    var params: MotionParams {
        switch self {
        case .drive: return .drive
        case .bike:  return .bike
        case .walk, .hold: return .walk
        }
    }
}

// MARK: - Physics per mode
//
// Cars brake harder than they accelerate and lose a lot of speed in a corner.
// Pedestrians barely change pace to turn, and rarely stop dead at a junction.
// Values are the ones locspoof uses on the PC side (motion.py).

struct MotionParams {
    /// m/s² pulling away
    let accel: Double
    /// m/s² braking, normally harder than accelerating
    let decel: Double
    /// m/s when no road data is available
    let defaultSpeed: Double
    /// m/s ceiling for the mode
    let maxSpeed: Double
    /// (turn angle in degrees, speed cap in m/s), ascending by angle
    let cornerSpeeds: [(angle: Double, cap: Double)]
    let junctionStopChance: Double
    let turnStopChance: Double
    /// seconds, uniform range
    let stopDwell: ClosedRange<Double>
    /// metres; never stop twice closer than this
    let stopGap: Double
    /// Real traffic controls from OSM: kind -> (chance, dwell range). When these
    /// are known, junctions are no longer guessed at and turns rarely stop.
    var controls: [String: (chance: Double, dwell: ClosedRange<Double>)] = [:]
    var turnStopChanceKnown: Double = 0

    static let drive = MotionParams(
        accel: 1.4, decel: 2.4, defaultSpeed: 13.4, maxSpeed: 40.0,
        cornerSpeeds: [(20, .infinity), (45, 11.0), (80, 7.0), (120, 4.5), (180, 3.0)],
        junctionStopChance: 0.15, turnStopChance: 0.45, stopDwell: 4.0...22.0,
        stopGap: 150,
        // Lights on a main road are timed, so a red is about one in three; a
        // stop sign almost always means a full stop, if a short one.
        controls: [
            "signal": (0.35, 8.0...45.0),
            "stop": (0.95, 1.0...4.0),
            "all_way_stop": (0.95, 1.0...5.0),
            "give_way": (0.15, 1.0...4.0)
        ],
        turnStopChanceKnown: 0.10
    )

    static let bike = MotionParams(
        accel: 0.9, decel: 1.8, defaultSpeed: 5.0, maxSpeed: 12.0,
        cornerSpeeds: [(25, .infinity), (60, 4.5), (100, 3.0), (180, 2.0)],
        junctionStopChance: 0.15, turnStopChance: 0.30, stopDwell: 3.0...15.0,
        stopGap: 80,
        controls: [
            "signal": (0.35, 8.0...40.0),
            "stop": (0.5, 1.0...3.0),
            "all_way_stop": (0.6, 1.0...3.0),
            "give_way": (0.1, 1.0...3.0)
        ],
        turnStopChanceKnown: 0.08
    )

    static let walk = MotionParams(
        accel: 0.6, decel: 0.9, defaultSpeed: 1.35, maxSpeed: 2.6,
        cornerSpeeds: [(60, .infinity), (120, 1.1), (180, 0.9)],
        junctionStopChance: 0.12, turnStopChance: 0.15, stopDwell: 2.0...12.0,
        stopGap: 40,
        // Walkers wait at crosswalk lights and ignore signs meant for cars.
        controls: ["signal": (0.5, 5.0...40.0)],
        turnStopChanceKnown: 0.05
    )

    /// How likely a stop is, given how fast the road is. Side streets on a
    /// 25 mph road often mean a light or a stop sign. On a 45 mph arterial most
    /// are the side street yielding to you, and on a highway nothing makes you
    /// stop dead short of traffic.
    static func stopScale(roadSpeed: Double) -> Double {
        if roadSpeed <= 11 { return 1 }                                // ~25 mph
        if roadSpeed <= 18 { return 1 - 0.7 * (roadSpeed - 11) / 7 }   // ~40 mph
        if roadSpeed <= 24 { return 0.3 - 0.3 * (roadSpeed - 18) / 6 } // ~54 mph
        return 0
    }

    func cornerCap(for angle: Double) -> Double {
        for corner in cornerSpeeds where angle <= corner.angle {
            return corner.cap
        }
        return cornerSpeeds.last?.cap ?? .infinity
    }
}

enum Units {
    static let mphToMps = 0.44704
    static let metersPerMile = 1609.344
}
