import Foundation
import CoreLocation

// MARK: - Playback state

enum PlaybackState: Equatable {
    case idle
    /// Moving along the route.
    case playing
    /// Stopped at a junction or turn; position frozen, wander still running.
    case waiting
    /// User paused; held at the current point.
    case paused
    /// Teleport mode; held at one point.
    case holding
    /// Reached the end; held there.
    case finished

    var isActive: Bool { self != .idle }
    var isMoving: Bool { self == .playing || self == .waiting }
}

struct PlaybackStats: Equatable {
    var speedMps: Double = 0
    var distance: Double = 0
    var length: Double = 0
    var remaining: TimeInterval = 0
    var dwellLeft: TimeInterval = 0
    var stopsLeft = 0
    var stopsTotal = 0
    var wanderMeters: Double = 0

    var speedMph: Double { speedMps / Units.mphToMps }
    var progress: Double { length > 0 ? min(distance / length, 1) : 0 }
}

// MARK: - RoutePlayer
//
// One 1 Hz wall-clock loop drives everything: moving along a route, waiting at
// stops, paused, teleported, finished. In every state it keeps sending a fix,
// because on iOS 17+ the simulated location is tied to the live session and a
// phone that stops hearing from us drifts back to its real position.
//
// Speed comes from the MotionPlan; position is integrated against the wall
// clock so a slow tick never makes the trip slower than planned.

@MainActor
final class RoutePlayer: ObservableObject {
    @Published private(set) var state: PlaybackState = .idle
    @Published private(set) var stats = PlaybackStats()
    /// What the iPhone was last told, wander included.
    @Published private(set) var reported: CLLocationCoordinate2D?
    @Published private(set) var problem: ConnectionProblem?

    var loop = false
    var pingPong = false
    var wanderEnabled = true {
        didSet { if !wanderEnabled { jitter = nil } }
    }

    private(set) var route: Polyline?
    private(set) var plan: MotionPlan?
    private var pending: [PlannedStop] = []
    private var distance: Double = 0
    private var direction: Double = 1
    private var dwellUntil: Date?
    /// True position while not moving (teleport, pause, finished).
    private var anchor: CLLocationCoordinate2D?
    private var jitter: GpsJitter?
    private var tickSource: DispatchSourceTimer?
    private var lastTick = Date()
    private var sending = false
    private var lease: DebugKeepAliveLease?

    private let simulator = LocationSimulator.shared
    private let tickInterval: TimeInterval = 1.0

    // MARK: - Controls

    func play(route: Polyline, plan: MotionPlan) {
        self.route = route
        self.plan = plan
        pending = plan.stops.sorted { $0.distance < $1.distance }
        distance = 0
        direction = 1
        dwellUntil = nil
        anchor = nil
        state = .playing
        begin()
    }

    /// Teleport. Calling again while holding moves the point immediately.
    /// Teleport: sit exactly on the spot. No GPS wander here; it only makes
    /// sense while moving along a route.
    func hold(at coordinate: CLLocationCoordinate2D) {
        route = nil
        plan = nil
        pending = []
        jitter = nil
        anchor = coordinate
        state = .holding
        begin()
    }

    func pause() {
        guard state.isMoving, let route else { return }
        anchor = route.position(at: distance).coordinate
        dwellUntil = nil
        state = .paused
        tick()
    }

    func resume() {
        guard state == .paused || state == .finished, route != nil else { return }
        if state == .finished {
            distance = 0
            direction = 1
            pending = plan?.stops.sorted { $0.distance < $1.distance } ?? []
        }
        anchor = nil
        lastTick = Date()
        state = .playing
    }

    func seek(to progress: Double) {
        guard let route else { return }
        distance = min(max(progress, 0), 1) * route.length
        pending = (plan?.stops ?? []).filter { $0.distance > distance }.sorted { $0.distance < $1.distance }
        if state == .waiting {
            dwellUntil = nil
            state = .playing
        }
        if !state.isMoving {
            anchor = route.position(at: distance).coordinate
        }
        updateStats(speed: state == .playing ? stats.speedMps : 0)
    }

    /// Stops simulating and gives the iPhone its real location back.
    func stop() {
        stopTicking()
        state = .idle
        route = nil
        plan = nil
        pending = []
        anchor = nil
        reported = nil
        stats = PlaybackStats()
        lease?.invalidate()
        lease = nil
        Task { await simulator.clear() }
    }

    // MARK: - Loop

    private func begin() {
        if wanderEnabled, route != nil, jitter == nil {
            jitter = GpsJitter()
        }
        if lease == nil {
            lease = DebugKeepAliveLease()
        }
        lastTick = Date()
        startTicking()
        tick()
    }

    private func startTicking() {
        guard tickSource == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + tickInterval, repeating: tickInterval, leeway: .milliseconds(50))
        source.setEventHandler { [weak self] in
            self?.tick()
        }
        source.resume()
        tickSource = source
    }

    private func stopTicking() {
        tickSource?.cancel()
        tickSource = nil
    }

    private func tick() {
        guard state.isActive else { return }

        let now = Date()
        // Cap dt so a long suspension doesn't teleport the phone down the road.
        let dt = min(max(now.timeIntervalSince(lastTick), 0), 5)
        lastTick = now

        if state == .waiting, let until = dwellUntil, now >= until {
            dwellUntil = nil
            state = .playing
        }

        var speed: Double = 0
        if state == .playing, let route, let plan {
            speed = plan.speed(at: distance)
            distance += speed * dt * direction

            // Reached the next stop: land on it exactly, then wait.
            if direction > 0, let next = pending.first, distance >= next.distance {
                pending.removeFirst()
                distance = next.distance
                dwellUntil = now.addingTimeInterval(next.dwell)
                state = .waiting
                speed = 0
            }

            if direction > 0, distance >= route.length {
                distance = route.length
                if pingPong {
                    direction = -1
                } else if loop {
                    distance = 0
                    pending = plan.stops.sorted { $0.distance < $1.distance }
                } else {
                    state = .finished
                    anchor = route.position(at: route.length).coordinate
                    speed = 0
                }
            } else if direction < 0, distance <= 0 {
                distance = 0
                direction = 1
                pending = plan.stops.sorted { $0.distance < $1.distance }
            }
        }

        let truePoint: CLLocationCoordinate2D?
        switch state {
        case .playing, .waiting:
            truePoint = route?.position(at: distance).coordinate
        case .paused, .holding, .finished:
            truePoint = anchor
        case .idle:
            truePoint = nil
        }
        guard let truePoint else { return }

        let point = jitter?.apply(to: truePoint, dt: dt, speed: speed) ?? truePoint
        reported = point
        updateStats(speed: speed)
        send(point)
    }

    private func send(_ point: CLLocationCoordinate2D) {
        // Never queue up fixes behind a slow reconnect; the next tick has a fresher one.
        guard !sending else { return }
        sending = true
        Task {
            let failure = await simulator.set(point)
            sending = false
            problem = failure
        }
    }

    private func updateStats(speed: Double) {
        var next = PlaybackStats()
        next.speedMps = speed
        next.wanderMeters = jitter?.offsetMeters ?? 0
        if let route, let plan {
            next.distance = distance
            next.length = route.length
            next.stopsTotal = plan.stops.count
            next.stopsLeft = pending.count
            next.dwellLeft = dwellUntil.map { max(0, $0.timeIntervalSinceNow) } ?? 0
            next.remaining = state == .finished ? 0 : plan.remainingDuration(from: distance) + next.dwellLeft
        }
        stats = next
    }
}
