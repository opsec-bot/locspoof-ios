//
//  TunnelManager.swift
//  locspoof
//
//  One place that knows whether the iPhone is reachable, and says so in words.
//

import Foundation

final class TunnelManager: ObservableObject {
    static let shared = TunnelManager()

    enum Status: Equatable {
        case idle
        case connecting
        case findingPort
        case connected
        case failed(ConnectionProblem)
    }

    @Published private(set) var status: Status = .idle

    var isConnected: Bool { status == .connected }

    private var isStarting = false

    private init() {
        NotificationCenter.default.addObserver(
            forName: .pairingFileImported, object: nil, queue: .main
        ) { [weak self] _ in
            self?.reconnectFromScratch()
        }
    }

    // MARK: - Status updates from the location session

    func noteLocationSessionUp() {
        runOnMain { self.status = .connected }
    }

    func noteFindingPort() {
        runOnMain { self.status = .findingPort }
    }

    func noteFailure(_ problem: ConnectionProblem) {
        runOnMain { self.status = .failed(problem) }
    }

    func markDisconnected() {
        runOnMain {
            if self.status == .connected { self.status = .idle }
        }
    }

    // MARK: - Connect

    /// Throws away both cached sessions and connects again. Used after a new
    /// pairing file or a port change.
    func reconnectFromScratch(showErrorUI: Bool = true) {
        JITEnableContext.shared.reset()
        LocationSimulator.shared.reset()
        status = .idle
        start(showErrorUI: showErrorUI)
    }

    func start(showErrorUI: Bool = true) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.start(showErrorUI: showErrorUI) }
            return
        }

        guard PairingFileStore.exists else {
            status = .failed(ConnectionProblem.from(code: -17, message: "Pairing file not found"))
            return
        }

        guard !isStarting else { return }
        isStarting = true
        status = .connecting

        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.connectFindingPortIfNeeded()
            DispatchQueue.main.async {
                self.finishStart(result, showErrorUI: showErrorUI)
            }
        }
    }

    /// Scans for the RemotePairing port by hand (Settings > Find Port).
    func findPort(completion: @escaping (UInt16?) -> Void) {
        status = .findingPort
        DispatchQueue.global(qos: .userInitiated).async {
            let port = PortFinder.find(host: DeviceConnectionContext.targetIPAddress)
            DispatchQueue.main.async {
                if let port {
                    DeviceConnectionContext.remotePairingPort = port
                    self.reconnectFromScratch(showErrorUI: false)
                } else {
                    self.status = .failed(ConnectionProblem.from(code: 61, message: "No RemotePairing port answered (connection refused)"))
                }
                completion(port)
            }
        }
    }

    private func connectFindingPortIfNeeded() -> Result<Void, NSError> {
        do {
            try JITEnableContext.shared.startTunnel()
            return .success(())
        } catch let error as NSError {
            let problem = ConnectionProblem.from(error: error)
            guard problem.kind == .portClosed, DeviceConnectionContext.autoFindPort else {
                return .failure(error)
            }

            noteFindingPort()
            guard let port = PortFinder.find(host: DeviceConnectionContext.targetIPAddress) else {
                return .failure(error)
            }
            LogManager.shared.addInfoLog("RemotePairing port moved to \(port)")
            DeviceConnectionContext.remotePairingPort = port
            LocationSimulator.shared.reset()
            do {
                try JITEnableContext.shared.startTunnel()
                return .success(())
            } catch let retryError as NSError {
                return .failure(retryError)
            }
        }
    }

    private func finishStart(_ result: Result<Void, NSError>, showErrorUI: Bool) {
        isStarting = false

        switch result {
        case .success:
            status = .connected
            LogManager.shared.addInfoLog("Tunnel connected on \(DeviceConnectionContext.endpointDescription)")
            mountDeveloperDiskImageIfNeeded()
        case .failure(let error):
            let problem = ConnectionProblem.from(error: error)
            status = .failed(problem)
            LogManager.shared.addErrorLog("Tunnel failed: \(problem.details)")
            if showErrorUI {
                showAlert(
                    title: problem.title,
                    message: problem.message,
                    showOk: false,
                    showTryAgain: true
                ) { shouldTryAgain in
                    if shouldTryAgain {
                        startTunnelInBackground()
                    }
                }
            }
        }
    }

    private func mountDeveloperDiskImageIfNeeded() {
        let trustcachePath = URL.documentsDirectory.appendingPathComponent("DDI/Image.dmg.trustcache").path
        guard FileManager.default.fileExists(atPath: trustcachePath),
              !MountingProgress.shared.coolisMounted,
              MountingProgress.shared.mountingThread == nil else {
            return
        }
        MountingProgress.shared.pubMount()
    }

    private func runOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}

func startTunnelInBackground(showErrorUI: Bool = true) {
    TunnelManager.shared.start(showErrorUI: showErrorUI)
}

func markTunnelDisconnected() {
    TunnelManager.shared.markDisconnected()
}
