import SwiftUI

@main
struct LocspoofApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var shouldAttemptTunnelReconnect = false

    init() {
        AppBootstrapper.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Theme.accent)
                .onOpenURL { url in
                    // locspoof:// links carry nothing yet; files are the real input.
                    guard url.isFileURL else { return }
                    AppModel.shared.open(url)
                }
                .task {
                    await downloadMissingDeveloperDiskImageFiles()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    handleScenePhaseChange(newPhase)
                }
        }
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .background:
            shouldAttemptTunnelReconnect = true
        case .active:
            if shouldAttemptTunnelReconnect {
                shouldAttemptTunnelReconnect = false
                if !TunnelManager.shared.isConnected {
                    startTunnelInBackground(showErrorUI: false)
                }
            }
        default:
            break
        }
    }

    private func downloadMissingDeveloperDiskImageFiles() async {
        do {
            try await DeveloperDiskImageService.shared.downloadMissingFiles()
        } catch {
            await MainActor.run {
                showAlert(
                    title: "Couldn't download the developer disk image",
                    message: "locspoof needs it once to turn on location simulation. Connect to the internet and reopen the app.\n\nDetails: \(error.localizedDescription)",
                    showOk: true
                )
            }
        }
    }
}
