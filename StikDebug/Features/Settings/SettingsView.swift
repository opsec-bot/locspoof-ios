import SwiftUI

struct SettingsView: View {
    @AppStorage(UserDefaults.Keys.targetDeviceIP) private var deviceIP = DeviceConnectionContext.defaultTargetIPAddress
    @AppStorage(UserDefaults.Keys.autoFindPort) private var autoFindPort = true
    @AppStorage("keepAliveAudio") private var keepAliveAudio = true
    @AppStorage("keepAliveLocation") private var keepAliveLocation = true
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true

    @StateObject private var tunnel = TunnelManager.shared
    @State private var portText = String(DeviceConnectionContext.remotePairingPort)
    @State private var isFindingPort = false
    @State private var showClearRoutesConfirm = false

    var body: some View {
        Form {
            connectionSection
            PairingSection()

            Section {
                Toggle("Silent audio", isOn: $keepAliveAudio)
                Toggle("Background location", isOn: $keepAliveLocation)
            } header: {
                Text("Keep running when locked")
            } footer: {
                Text("Keep both on. Without them iOS pauses locspoof when the screen locks and the iPhone drifts back to its real location.")
            }

            Section("Data") {
                Button("Delete all saved routes", role: .destructive) {
                    showClearRoutesConfirm = true
                }
            }

            Section("Setup") {
                Button("Show setup again") {
                    hasCompletedOnboarding = false
                }
            }

            Section {
                LabeledContent("Version", value: appVersion)
                LabeledContent("Built on", value: "RouteSim, StikDebug, idevice")
            } header: {
                Text("About")
            } footer: {
                Text("locspoof changes the GPS position apps see. It can't fake motion sensors, so apps that also read the accelerometer (like Life360's driving detection) may not always agree.")
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Delete all saved routes?", isPresented: $showClearRoutesConfirm, titleVisibility: .visible) {
            Button("Delete all", role: .destructive) {
                RouteStore.shared.routes.forEach { RouteStore.shared.delete($0) }
            }
        }
        .onReceive(tunnel.$status) { _ in
            portText = String(DeviceConnectionContext.remotePairingPort)
        }
    }

    // MARK: - Connection

    private var connectionSection: some View {
        Section {
            Button {
                AppModel.shared.showDoctor = true
            } label: {
                HStack {
                    Circle().fill(tunnel.status.color).frame(width: 10, height: 10)
                    Text(tunnel.status.label)
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Text("Run checks")
                        .font(.footnote)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }

            HStack {
                Text("Port")
                Spacer()
                TextField("49152", text: $portText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 80)
                    .onSubmit(applyPort)
                Button(isFindingPort ? "Finding…" : "Find port") {
                    isFindingPort = true
                    tunnel.findPort { port in
                        isFindingPort = false
                        if let port { portText = String(port) }
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isFindingPort)
            }

            Toggle("Find the port automatically", isOn: $autoFindPort)

            HStack {
                Text("LocalDevVPN address")
                Spacer()
                TextField(DeviceConnectionContext.defaultTargetIPAddress, text: $deviceIP)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 120)
            }

            Button("Reconnect") {
                applyPort()
                tunnel.reconnectFromScratch()
            }
        } header: {
            Text("Connection")
        } footer: {
            Text("Your iPhone picks a new connection port every time it restarts. locspoof finds it by itself; Find port does it now.")
        }
    }

    private func applyPort() {
        guard let port = UInt16(portText.trimmingCharacters(in: .whitespaces)), port > 0 else {
            portText = String(DeviceConnectionContext.remotePairingPort)
            return
        }
        if port != DeviceConnectionContext.remotePairingPort {
            DeviceConnectionContext.remotePairingPort = port
            tunnel.reconnectFromScratch(showErrorUI: false)
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

// MARK: - Pairing file

/// Import or replace the pairing file in place. Replacing reconnects right
/// away, so a new file never needs a reinstall.
struct PairingSection: View {
    @State private var showPicker = false
    @State private var info = PairingFileStore.info
    @State private var exists = PairingFileStore.exists
    @State private var message: String?

    var body: some View {
        Section {
            if exists {
                LabeledContent("Host ID", value: info.map { String($0.identifier.prefix(8)) + "…" } ?? "unreadable")
                if let date = info?.importedAt {
                    LabeledContent("Imported", value: date.formatted(date: .abbreviated, time: .shortened))
                }
            }
            Button(exists ? "Replace pairing file" : "Import pairing file") {
                showPicker = true
            }
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Pairing file")
        } footer: {
            Text("Accepts .plist, .mobiledevicepairing and .mobiledevicepair. You can also tap the file in Files or a chat and open it with locspoof. Make it on the PC with: python -m pymobiledevice3 lockdown remotepairing --pair")
        }
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: PairingFileStore.supportedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    try PairingFileStore.importFile(at: url)
                    message = "Imported. Reconnecting…"
                } catch {
                    message = error.localizedDescription
                }
            case .failure(let error):
                message = error.localizedDescription
            }
            refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pairingFileImported)) { _ in
            refresh()
        }
    }

    private func refresh() {
        info = PairingFileStore.info
        exists = PairingFileStore.exists
    }
}
