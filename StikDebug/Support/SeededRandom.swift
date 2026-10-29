import Foundation

/// SplitMix64. Small, fast, and seedable, so the motion plan and the GPS wander
/// can be reproduced exactly in tests while still being random in the app.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    init() {
        state = UInt64.random(in: .min ... .max)
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    /// Standard normal sample (Box-Muller).
    mutating func gaussian() -> Double {
        let u1 = max(unit(), .leastNonzeroMagnitude)
        let u2 = unit()
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }

    mutating func uniform(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * unit()
    }
}
