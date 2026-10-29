import MapKit
import SwiftUI

struct MapScreen: View {
    @ObservedObject var vm: MapViewModel
    @StateObject private var tunnel = TunnelManager.shared
    @State private var showSearch = false
    @State private var showOptions = false
    @State private var showSave = false
    @State private var showImporter = false

    var body: some View {
        ZStack(alignment: .top) {
            map
            VStack(spacing: 8) {
                topBar
                if let notice = vm.notice {
                    NoticeBanner(text: notice) { vm.notice = nil }
                }
                Spacer()
                ControlPanel(
                    vm: vm,
                    showOptions: $showOptions,
                    showSave: $showSave,
                    showImporter: $showImporter
                )
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $showSearch) {
            SearchView(near: vm.player.reported ?? DeviceLocationManager.shared.coordinate) { place in
                vm.addPlace(place)
            }
        }
        .sheet(isPresented: $showOptions) {
            OptionsSheet(vm: vm)
        }
        .sheet(isPresented: $showSave) {
            SaveRouteSheet(name: $vm.routeName) { vm.saveRoute() }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: GPXImporter.supportedTypes,
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                vm.importRoute(from: url)
            }
        }
        .onAppear {
            DeviceLocationManager.shared.requestAuthorizationIfNeeded()
            DeviceLocationManager.shared.startUpdating()
        }
        .task(id: vm.notice) {
            guard vm.notice != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            vm.notice = nil
        }
    }

    // MARK: - Map

    private var map: some View {
        MapReader { proxy in
            Map(position: $vm.cameraPosition) {
                UserAnnotation()

                if vm.routePoints.count >= 2 {
                    MapPolyline(coordinates: vm.routePoints)
                        .stroke(Theme.routeLine, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }

                ForEach(Array(vm.waypoints.enumerated()), id: \.element.id) { index, waypoint in
                    Annotation(waypoint.name ?? "", coordinate: waypoint.coordinate) {
                        WaypointPin(index: index, count: vm.waypoints.count, isHold: vm.mode == .hold)
                    }
                }

                ForEach(Array(vm.stopPoints.enumerated()), id: \.offset) { _, point in
                    Annotation("", coordinate: point) {
                        Circle()
                            .fill(Theme.caution)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(Theme.panel, lineWidth: 1.5))
                    }
                }

                if let reported = vm.player.reported {
                    Annotation("Spoofed", coordinate: reported) {
                        SpoofedDot()
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .onTapGesture { point in
                if let coordinate = proxy.convert(point, from: .local) {
                    vm.handleTap(coordinate)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 8) {
            Button {
                AppModel.shared.showDoctor = true
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(tunnel.status.color)
                        .frame(width: 8, height: 8)
                    Text(tunnel.status.label)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Theme.panel, in: Capsule())
                .overlay(Capsule().stroke(Theme.raised, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                showSearch = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .background(Theme.panel, in: Circle())
                    .overlay(Circle().stroke(Theme.raised, lineWidth: 1))
            }
            .accessibilityLabel("Search places")

            Button {
                vm.addMyLocation()
            } label: {
                Image(systemName: "location")
                    .font(.body.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .background(Theme.panel, in: Circle())
                    .overlay(Circle().stroke(Theme.raised, lineWidth: 1))
            }
            .accessibilityLabel("Use my location")
        }
        .padding(.top, 4)
    }
}

// MARK: - Pins

private struct WaypointPin: View {
    let index: Int
    let count: Int
    let isHold: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(fill)
                .frame(width: 26, height: 26)
                .overlay(Circle().stroke(Theme.panel, lineWidth: 2))
            if isHold {
                Image(systemName: "mappin")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.panel)
            } else {
                Text(label)
                    .font(.caption.bold())
                    .foregroundStyle(Theme.panel)
            }
        }
    }

    private var label: String {
        if index == 0 { return "A" }
        if index == count - 1 { return "B" }
        return "\(index)"
    }

    private var fill: Color {
        if isHold { return Theme.accent }
        if index == 0 { return Theme.good }
        if index == count - 1 { return Theme.bad }
        return Theme.ink
    }
}

private struct SpoofedDot: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.accent.opacity(0.25))
                .frame(width: 34, height: 34)
            Circle()
                .fill(Theme.accent)
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(Theme.panel, lineWidth: 3))
        }
    }
}

private struct NoticeBanner: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Save sheet

struct SaveRouteSheet: View {
    @Binding var name: String
    var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Route name", text: $name)
            }
            .navigationTitle("Save route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(); dismiss() }
                }
            }
        }
        .presentationDetents([.height(200)])
    }
}
