import Darwin
import SwiftUI

// MARK: - Checks
//
// Runs each link of the chain in order and stops at the first one that fails,
// so the answer is "this step is broken, do this", not a wall of text.

struct DoctorCheck: Identifiable {
    enum Result: Equatable {
        case pending, running, ok(String), warning(String), failed(String)
    }

    let id: String
    let title: String
    var result: Result = .pending
    var problem: ConnectionProblem?
}

@MainActor
final class ConnectionDoctor: ObservableObject {
    @Published private(set) var checks: [DoctorCheck] = ConnectionDoctor.freshChecks()
    @Published private(set) var isRunning = false
    @Published private(set) var scanProgress: Double?

    private static func freshChecks() -> [DoctorCheck] {
        [
            DoctorCheck(id: "pairing", title: "Pairing file"),
            DoctorCheck(id: "vpn", title: "LocalDevVPN"),
            DoctorCheck(id: "port", title: "Connection port"),
            DoctorCheck(id: "tunnel", title: "Developer tunnel"),
            DoctorCheck(id: "ddi", title: "Developer disk image")
        ]
    }

    func run() async {
        guard !isRunning else { return }
        isRunning = true
        checks = Self.freshChecks()
        defer {
            isRunning = false
            scanProgress = nil
        }

        // 1. Pairing file
        set("pairing", .running)
        guard let data = try? Data(contentsOf: PairingFileStore.prepareURL()) else {
            fail("pairing", "No pairing file imported.", ConnectionProblem.from(code: -17, message: "Pairing file not found"))
            return
        }
        do {
            try PairingFileStore.validate(data)
            let id = PairingFileStore.info?.identifier.prefix(8) ?? "?"
            set("pairing", .ok("Looks valid (host \(id)…)."))
        } catch {
            set("pairing", .failed(error.localizedDescription))
            return
        }

        // 2. VPN interface
        set("vpn", .running)
        if let vpn = Self.vpnInterface() {
            set("vpn", .ok("Up (\(vpn))."))
        } else {
            set("vpn", .warning("No VPN interface seen. Open LocalDevVPN and connect it. If it's already on, ignore this."))
        }

        // 3. Port
        set("port", .running)
        let host = DeviceConnectionContext.targetIPAddress
        let saved = DeviceConnectionContext.remotePairingPort
        let port: UInt16? = await Task.detached { () -> UInt16? in
            if PortFinder.speaksRemotePairing(host: host, port: saved) { return saved }
            return PortFinder.find(host: host) { fraction in
                Task { @MainActor in self.scanProgress = fraction }
            }
        }.value
        scanProgress = nil
        guard let port else {
            fail("port", "No port answered on \(host).", ConnectionProblem.from(code: 61, message: "No RemotePairing port answered (connection refused)"))
            return
        }
        if port != saved {
            DeviceConnectionContext.remotePairingPort = port
            JITEnableContext.shared.reset()
            LocationSimulator.shared.reset()
            set("port", .ok("Moved to \(port). Saved it."))
        } else {
            set("port", .ok("Port \(port) is answering."))
        }

        // 4. Tunnel
        set("tunnel", .running)
        let tunnelError: NSError? = await Task.detached { () -> NSError? in
            JITEnableContext.shared.reset()
            do {
                try JITEnableContext.shared.startTunnel()
                return nil
            } catch {
                return error as NSError
            }
        }.value
        if let tunnelError {
            let problem = ConnectionProblem.from(error: tunnelError)
            fail("tunnel", problem.title, problem)
            TunnelManager.shared.noteFailure(problem)
            return
        }
        set("tunnel", .ok("Connected."))
        TunnelManager.shared.noteLocationSessionUp()

        // 5. Disk image
        set("ddi", .running)
        if setupInstallsDiskImage {
            set("ddi", .ok("iOS 27 or newer: locspoof Setup installs this from a computer. If the location doesn't move, plug in and run Setup again."))
            return
        }
        let mount: MountCheckResult = await Task.detached { () -> MountCheckResult in checkMountStatus() }.value
        switch mount {
        case .mounted:
            set("ddi", .ok("Mounted. Location simulation is ready."))
        case .notMounted:
            MountingProgress.shared.pubMount()
            set("ddi", .warning("Not mounted yet. Mounting now; give it a few seconds."))
        case .unreachable:
            fail("ddi", "Couldn't ask the iPhone.", ConnectionProblem.from(code: -1, message: "Developer disk image check failed"))
        }
    }

    private func set(_ id: String, _ result: DoctorCheck.Result) {
        guard let index = checks.firstIndex(where: { $0.id == id }) else { return }
        checks[index].result = result
    }

    private func fail(_ id: String, _ text: String, _ problem: ConnectionProblem) {
        guard let index = checks.firstIndex(where: { $0.id == id }) else { return }
        checks[index].result = .failed(text)
        checks[index].problem = problem
    }

    /// First utun interface with an IPv4 address, e.g. "utun4 10.7.0.0".
    static func vpnInterface() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let name = String(cString: entry.pointee.ifa_name)
            guard name.hasPrefix("utun"),
                  let address = entry.pointee.ifa_addr,
                  address.pointee.sa_family == sa_family_t(AF_INET) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            return "\(name) \(String(cString: host))"
        }
        return nil
    }
}

// MARK: - View

struct DoctorView: View {
    @StateObject private var doctor = ConnectionDoctor()
    @StateObject private var tunnel = TunnelManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                ForEach(doctor.checks) { check in
                    CheckRow(check: check, scanProgress: check.id == "port" ? doctor.scanProgress : nil)
                }
            } footer: {
                Text("Runs each step in order and stops at the first one that fails.")
            }

            if let problem = doctor.checks.compactMap(\.problem).first {
                Section(problem.title) {
                    Text(problem.explanation)
                    ForEach(Array(problem.steps.enumerated()), id: \.offset) { index, step in
                        Label {
                            Text(step)
                        } icon: {
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .frame(width: 22, height: 22)
                                .background(Theme.raised, in: Circle())
                        }
                    }
                    DisclosureGroup("Details") {
                        Text(problem.details)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            } else if case .failed(let problem) = tunnel.status, !doctor.isRunning, doctor.checks.allSatisfy({ $0.result == .pending }) {
                Section("Last error: \(problem.title)") {
                    Text(problem.explanation)
                    ForEach(Array(problem.steps.enumerated()), id: \.offset) { index, step in
                        Text("\(index + 1). \(step)")
                    }
                }
            }

            Section {
                Button {
                    Task { await doctor.run() }
                } label: {
                    HStack {
                        if doctor.isRunning { ProgressView() }
                        Text(doctor.isRunning ? "Checking…" : "Run checks")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(doctor.isRunning)
            }
        }
        .navigationTitle("Connection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .task {
            await doctor.run()
        }
    }
}

private struct CheckRow: View {
    let check: DoctorCheck
    let scanProgress: Double?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            icon
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(check.title)
                    .font(.body.weight(.semibold))
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let scanProgress {
                    ProgressView(value: scanProgress)
                    Text("Scanning ports for the new one…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var icon: some View {
        switch check.result {
        case .pending:
            Image(systemName: "circle").foregroundStyle(.tertiary)
        case .running:
            ProgressView()
        case .ok:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
        case .warning:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.caution)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.bad)
        }
    }

    private var detail: String? {
        switch check.result {
        case .pending, .running: return nil
        case .ok(let text), .warning(let text), .failed(let text): return text
        }
    }
}
