import Foundation
import SwiftUI

/// App-wide state: which tab is showing and the one map model every tab shares,
/// so loading a route from the Library lands on the map ready to go.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    enum Tab: Hashable {
        case map, library, settings
    }

    @Published var tab: Tab = .map
    @Published var showDoctor = false

    let map = MapViewModel()

    private static let routeExtensions: Set<String> = ["gpx", "kml", "geojson", "json", "csv", "txt"]

    /// Files opened from Files, AirDrop, Messages or a chat download.
    func open(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        if Self.routeExtensions.contains(ext) {
            map.importRoute(from: url)
            tab = .map
            return
        }

        do {
            try PairingFileStore.importFile(at: url)
            showAlert(
                title: "Pairing file imported",
                message: "locspoof is reconnecting with the new file. No reinstall needed.",
                showOk: true
            )
        } catch {
            showAlert(title: "Couldn't import that file", message: error.localizedDescription, showOk: true)
        }
    }

    func load(_ route: SavedRoute) {
        map.load(route)
        tab = .map
    }
}
