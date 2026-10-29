import SwiftUI
import UIKit

struct RouteLibraryView: View {
    @StateObject private var store = RouteStore.shared
    @State private var routeToDelete: SavedRoute?
    @State private var showImporter = false

    var body: some View {
        Group {
            if store.routes.isEmpty {
                emptyState
            } else {
                routeList
            }
        }
        .navigationTitle("Routes")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showImporter = true
                } label: {
                    Label("Import GPX", systemImage: "doc.badge.plus")
                }
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: GPXImporter.supportedTypes,
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                AppModel.shared.map.importRoute(from: url)
                AppModel.shared.tab = .map
            }
        }
        .confirmationDialog(
            "Delete \(routeToDelete?.name ?? "route")?",
            isPresented: Binding(get: { routeToDelete != nil }, set: { if !$0 { routeToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let route = routeToDelete { store.delete(route) }
                routeToDelete = nil
            }
        }
    }

    private var routeList: some View {
        List {
            ForEach(store.routes) { route in
                Button {
                    AppModel.shared.load(route)
                } label: {
                    RouteRow(route: route)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        routeToDelete = route
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        shareGPX(route)
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .tint(Theme.accent)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No saved routes")
                .font(.title3.bold())
            Text("Build a route on the map and pick Save from the ••• menu, or import a GPX from locspoof on your PC.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Import GPX") { showImporter = true }
                .buttonStyle(.bordered)
        }
    }

    private func shareGPX(_ route: SavedRoute) {
        let data = RouteStore.shared.exportGPX(route)
        let safeName = route.name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName).gpx")
        try? data.write(to: url)
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        top.present(sheet, animated: true)
    }
}

private struct RouteRow: View {
    let route: SavedRoute

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: route.mode.systemImage)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(route.name)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var detail: String {
        let miles = route.totalDistanceMeters / Units.metersPerMile
        var parts = [route.mode.displayName, String(format: "%.1f mi", miles), "\(route.waypoints.count) points"]
        if let cap = route.speedCapMph { parts.append("max \(Int(cap)) mph") }
        return parts.joined(separator: " · ")
    }
}
