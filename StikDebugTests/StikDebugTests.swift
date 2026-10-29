import CoreLocation
import XCTest
@testable import StikDebug

final class MotionPlanTests: XCTestCase {
    /// About 1.1 km due north from a point in Dallas.
    private let straight = Polyline([
        CLLocationCoordinate2D(latitude: 32.9500, longitude: -96.8900),
        CLLocationCoordinate2D(latitude: 32.9600, longitude: -96.8900)
    ])

    func testStartsAndEndsNearStandstill() {
        let plan = MotionPlan.build(route: straight, mode: .drive, speedCap: nil, seed: 1)
        XCTAssertLessThanOrEqual(plan.speeds.first!, MotionPlan.stopFloor + 0.001)
        XCTAssertLessThanOrEqual(plan.speeds.last!, MotionPlan.stopFloor + 0.001)
    }

    func testCruisesAtDefaultSpeedMidRoute() {
        let plan = MotionPlan.build(route: straight, mode: .drive, speedCap: nil, seed: 1)
        XCTAssertEqual(plan.speed(at: straight.length / 2), MotionParams.drive.defaultSpeed, accuracy: 0.01)
    }

    func testSpeedCapIsACeiling() {
        let cap = 20 * Units.mphToMps
        let plan = MotionPlan.build(route: straight, mode: .drive, speedCap: cap, seed: 1)
        XCTAssertLessThanOrEqual(plan.speeds.max()!, cap + 0.001)
    }

    func testAccelerationIsPhysicallyReachable() {
        let plan = MotionPlan.build(route: straight, mode: .drive, speedCap: nil, seed: 1)
        let accel = MotionParams.drive.accel
        for i in 1..<plan.speeds.count {
            let reachable = (plan.speeds[i - 1] * plan.speeds[i - 1] + 2 * accel * plan.step).squareRoot()
            XCTAssertLessThanOrEqual(plan.speeds[i], reachable + 1e-9)
        }
    }

    func testRightAngleCornerSlowsTheCar() {
        let corner = Polyline([
            CLLocationCoordinate2D(latitude: 32.9500, longitude: -96.8900),
            CLLocationCoordinate2D(latitude: 32.9600, longitude: -96.8900),
            CLLocationCoordinate2D(latitude: 32.9600, longitude: -96.8780)
        ])
        let plan = MotionPlan.build(route: corner, mode: .drive, speedCap: nil, stopsEnabled: false, seed: 1)
        let atCorner = plan.speed(at: corner.cumulative[1])
        XCTAssertLessThanOrEqual(atCorner, 4.5 + 0.001)
    }

    func testStopsRespectSpacingAndEnds() {
        let candidates = stride(from: 0.0, through: straight.length, by: 10).map { $0 }
        let plan = MotionPlan.build(route: straight, mode: .drive, speedCap: nil, turns: candidates, seed: 7)
        XCTAssertFalse(plan.stops.isEmpty)
        for stop in plan.stops {
            XCTAssertGreaterThanOrEqual(stop.distance, 15)
            XCTAssertLessThanOrEqual(stop.distance, straight.length - 15)
        }
        for (a, b) in zip(plan.stops, plan.stops.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b.distance - a.distance, 40)
        }
    }

    func testSameSeedSamePlan() {
        let turns = [200.0, 500.0, 800.0]
        let a = MotionPlan.build(route: straight, mode: .bike, speedCap: nil, turns: turns, seed: 42)
        let b = MotionPlan.build(route: straight, mode: .bike, speedCap: nil, turns: turns, seed: 42)
        XCTAssertEqual(a.stops, b.stops)
        XCTAssertEqual(a.speeds, b.speeds)
    }

    func testEmptyAndSinglePointRoutesDoNotCrash() {
        _ = MotionPlan.build(route: Polyline([]), mode: .walk, speedCap: nil)
        _ = MotionPlan.build(route: Polyline([CLLocationCoordinate2D(latitude: 1, longitude: 1)]), mode: .walk, speedCap: nil)
    }
}

final class GpsJitterTests: XCTestCase {
    func testWanderStaysWithinAFewMetres() {
        let jitter = GpsJitter(seed: 3)
        var worst = 0.0
        for _ in 0..<3600 {
            jitter.advance(dt: 1, speed: 0)
            worst = max(worst, jitter.offsetMeters)
        }
        // Mean-reverting: 3 m sigma should essentially never pass 20 m.
        XCTAssertLessThan(worst, 20)
        XCTAssertGreaterThan(worst, 0.5)
    }

    func testWanderIsCorrelatedNotStatic() {
        let jitter = GpsJitter(seed: 9)
        var steps: [Double] = []
        var previous = (jitter.east, jitter.north)
        for _ in 0..<600 {
            jitter.advance(dt: 1, speed: 0)
            steps.append(hypot(jitter.east - previous.0, jitter.north - previous.1))
            previous = (jitter.east, jitter.north)
        }
        let meanStep = steps.reduce(0, +) / Double(steps.count)
        // Successive fixes move a little, far less than the full spread.
        XCTAssertLessThan(meanStep, GpsJitter.stillSigma)
    }

    func testMovingTightensTheFix() {
        XCTAssertEqual(GpsJitter.sigma(forSpeed: 0), GpsJitter.stillSigma)
        XCTAssertEqual(GpsJitter.sigma(forSpeed: 20), GpsJitter.movingSigma)
    }
}

final class PairingFileTests: XCTestCase {
    private func plist(_ dict: [String: Any]) -> Data {
        try! PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }

    func testAcceptsRemotePairingRecord() {
        XCTAssertNoThrow(try PairingFileStore.validate(plist([
            "identifier": "00000000-0000-4000-8000-000000000000",
            "private_key": Data(repeating: 1, count: 32),
            "public_key": Data(repeating: 2, count: 32)
        ])))
    }

    func testRejectsLockdownRecordWithClearError() {
        XCTAssertThrowsError(try PairingFileStore.validate(plist([
            "HostCertificate": Data(), "DeviceCertificate": Data(), "HostID": "x"
        ]))) { error in
            guard case PairingFileError.lockdownRecord = error else {
                return XCTFail("expected lockdownRecord, got \(error)")
            }
        }
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try PairingFileStore.validate(Data("hello".utf8)))
    }
}

final class ConnectionProblemTests: XCTestCase {
    func testRefusedMeansPortClosed() {
        let problem = ConnectionProblem.from(code: 16, message: #"InternalError("connect: Connection refused (os error 61)")"#)
        XCTAssertEqual(problem.kind, .portClosed)
    }

    func testTimeoutAndReset() {
        XCTAssertEqual(ConnectionProblem.from(code: 1, message: "operation timed out").kind, .timedOut)
        XCTAssertEqual(ConnectionProblem.from(code: 54, message: "Connection reset by peer").kind, .connectionReset)
    }
}

final class RoutePlannerTests: XCTestCase {
    func testParsesCoordinates() {
        let c = RoutePlanner.parseCoordinate("32.95, -96.89")
        XCTAssertEqual(c?.latitude ?? 0, 32.95, accuracy: 1e-9)
        XCTAssertEqual(c?.longitude ?? 0, -96.89, accuracy: 1e-9)
        XCTAssertNil(RoutePlanner.parseCoordinate("Dallas"))
        XCTAssertNil(RoutePlanner.parseCoordinate("95, 10"))
    }

    func testPolylineLengthAndPosition() {
        let line = Polyline([
            CLLocationCoordinate2D(latitude: 0, longitude: 0),
            CLLocationCoordinate2D(latitude: 0.01, longitude: 0)
        ])
        XCTAssertEqual(line.length, 1105, accuracy: 10)
        let mid = line.position(at: line.length / 2).coordinate
        XCTAssertEqual(mid.latitude, 0.005, accuracy: 1e-6)
    }
}
