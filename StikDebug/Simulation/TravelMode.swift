import CoreLocation

// MARK: - Travel mode

enum TravelMode: String, Codable, CaseIterable, Identifiable {
    case drive
    case bike
    case walk
    /// Sit at one point. No route, just a held location with GPS wander.
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

    static let drive = MotionParams(
        accel: 1.4, decel: 2.4, defaultSpeed: 13.4, maxSpeed: 40.0,
        cornerSpeeds: [(20, .infinity), (45, 11.0), (80, 7.0), (120, 4.5), (180, 3.0)],
        junctionStopChance: 0.30, turnStopChance: 0.55, stopDwell: 4.0...22.0
    )

    static let bike = MotionParams(
        accel: 0.9, decel: 1.8, defaultSpeed: 5.0, maxSpeed: 12.0,
        cornerSpeeds: [(25, .infinity), (60, 4.5), (100, 3.0), (180, 2.0)],
        junctionStopChance: 0.22, turnStopChance: 0.35, stopDwell: 3.0...15.0
    )

    static let walk = MotionParams(
        accel: 0.6, decel: 0.9, defaultSpeed: 1.35, maxSpeed: 2.6,
        cornerSpeeds: [(60, .infinity), (120, 1.1), (180, 0.9)],
        junctionStopChance: 0.12, turnStopChance: 0.15, stopDwell: 2.0...12.0
    )

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
