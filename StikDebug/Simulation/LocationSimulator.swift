import Foundation
import CoreLocation

// MARK: - LocationSimulator
//
// Thread-safe wrapper over the C bridge. Every bridge call runs on
// LocationSimulationCommandQueue.shared (serial).
//
// When the iPhone refuses the connection, the usual reason is that it picked a
// new RemotePairing port after a restart. In that case this finds the new port
// once and retries, instead of failing with "connection refused".

final class LocationSimulator {
    static let shared = LocationSimulator()

    private let queue = LocationSimulationCommandQueue.shared

    private init() {}

    /// Sends one coordinate. Returns nil on success.
    func set(_ coordinate: CLLocationCoordinate2D) async -> ConnectionProblem? {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.setOnQueue(coordinate))
            }
        }
    }

    /// Stops simulating; the iPhone goes back to its real location.
    func clear() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                _ = clear_simulated_location()
                continuation.resume()
            }
        }
    }

    /// Drops the cached session (new pairing file, new port).
    func reset() {
        queue.async {
            reset_location_simulation()
        }
    }

    private func setOnQueue(_ coordinate: CLLocationCoordinate2D) -> ConnectionProblem? {
        var status = send(coordinate)
        if status == LocationSimulationStatus.ok {
            TunnelManager.shared.noteLocationSessionUp()
            return nil
        }

        if status == LocationSimulationStatus.providerCreate,
           DeviceConnectionContext.autoFindPort,
           isRefused(last_location_simulation_error()) {
            TunnelManager.shared.noteFindingPort()
            if let port = PortFinder.find(host: DeviceConnectionContext.targetIPAddress) {
                LogManager.shared.addInfoLog("RemotePairing port moved to \(port)")
                DeviceConnectionContext.remotePairingPort = port
                JITEnableContext.shared.reset()
                status = send(coordinate)
                if status == LocationSimulationStatus.ok {
                    TunnelManager.shared.noteLocationSessionUp()
                    return nil
                }
            }
        }

        let problem = problem(for: status)
        TunnelManager.shared.noteFailure(problem)
        return problem
    }

    private func send(_ coordinate: CLLocationCoordinate2D) -> Int32 {
        simulate_location(
            DeviceConnectionContext.targetIPAddress,
            coordinate.latitude,
            coordinate.longitude,
            PairingFileStore.prepareURL().path
        )
    }

    private func isRefused(_ error: (code: Int, message: String)?) -> Bool {
        guard let error else { return false }
        let lower = error.message.lowercased()
        return lower.contains("refused") || lower.contains("os error 61")
    }

    private func problem(for status: Int32) -> ConnectionProblem {
        if let error = last_location_simulation_error() {
            return ConnectionProblem.from(code: error.code, message: error.message)
        }
        switch status {
        case LocationSimulationStatus.pairingRead:
            return ConnectionProblem.from(code: -17, message: "Pairing file not found or unreadable")
        case LocationSimulationStatus.invalidIP:
            return ConnectionProblem.from(code: -18, message: "Device IP address is not valid")
        default:
            return ConnectionProblem.from(code: Int(status), message: "Location simulation failed at step \(status)")
        }
    }
}
