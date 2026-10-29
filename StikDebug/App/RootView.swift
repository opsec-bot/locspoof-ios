import SwiftUI

struct RootView: View {
    @StateObject private var app = AppModel.shared
    @StateObject private var tunnelManager = TunnelManager.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        if hasCompletedOnboarding {
            mainTabs
                .onAppear {
                    if !tunnelManager.isConnected {
                        startTunnelInBackground(showErrorUI: false)
                    }
                }
        } else {
            OnboardingView {
                hasCompletedOnboarding = true
                startTunnelInBackground(showErrorUI: false)
            }
        }
    }

    private var mainTabs: some View {
        TabView(selection: $app.tab) {
            MapScreen(vm: app.map)
                .tabItem { Label("Map", systemImage: "location.fill") }
                .tag(AppModel.Tab.map)

            NavigationStack {
                RouteLibraryView()
            }
            .tabItem { Label("Routes", systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill") }
            .tag(AppModel.Tab.library)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(AppModel.Tab.settings)
        }
        .sheet(isPresented: $app.showDoctor) {
            NavigationStack {
                DoctorView()
            }
        }
    }
}
