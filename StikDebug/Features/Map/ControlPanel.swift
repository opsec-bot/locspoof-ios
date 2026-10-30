import SwiftUI

struct ControlPanel: View {
    @ObservedObject var vm: MapViewModel
    @Binding var showOptions: Bool
    @Binding var showSave: Bool
    @Binding var showImporter: Bool

    var body: some View {
        VStack(spacing: 12) {
            if vm.isActive {
                livePanel
            } else {
                editPanel
            }
        }
        .padding(16)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.raised, lineWidth: 1))
    }

    // MARK: - Editing

    private var editPanel: some View {
        VStack(spacing: 12) {
            modePicker

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(summaryTitle)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Text(vm.hint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                editMenu
            }

            if vm.mode.isRoute {
                HStack(spacing: 8) {
                    chip(speedLabel, systemImage: "speedometer") { showOptions = true }
                    chip(vm.stopsEnabled ? "Stops on" : "Stops off", systemImage: "hand.raised") { showOptions = true }
                    chip(vm.wander ? "Wander on" : "Wander off", systemImage: "dot.radiowaves.left.and.right") { showOptions = true }
                }
            }

            Button(action: vm.start) {
                HStack {
                    if vm.isRouting {
                        ProgressView().tint(Theme.panel)
                    }
                    Text(startTitle)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .foregroundStyle(Color.white.opacity(0.97))
                .background(vm.canStart ? Theme.accent : Theme.accent.opacity(0.35),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!vm.canStart)
        }
    }

    private var modePicker: some View {
        HStack(spacing: 6) {
            ForEach(TravelMode.allCases) { mode in
                let selected = vm.mode == mode
                Button {
                    vm.setMode(mode)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: mode.systemImage)
                            .font(.body.weight(.semibold))
                        Text(mode.displayName)
                            .font(.caption2.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .foregroundStyle(selected ? Theme.accent : Theme.ink.opacity(0.7))
                    .background(selected ? Theme.accent.opacity(0.14) : Theme.raised,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(selected ? Theme.accent : .clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var editMenu: some View {
        Menu {
            Button("Undo last point", systemImage: "arrow.uturn.backward") { vm.undoLast() }
                .disabled(vm.waypoints.isEmpty)
            if vm.mode.isRoute {
                Button("Reverse route", systemImage: "arrow.left.arrow.right") { vm.reverse() }
                    .disabled(vm.waypoints.count < 2)
            }
            Button("Save route", systemImage: "square.and.arrow.down") { showSave = true }
                .disabled(vm.waypoints.isEmpty)
            Button("Import GPX", systemImage: "doc.badge.plus") { showImporter = true }
            Button("Options", systemImage: "slider.horizontal.3") { showOptions = true }
            Button("Clear", systemImage: "trash", role: .destructive) { vm.clear() }
                .disabled(vm.waypoints.isEmpty)
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.bold))
                .frame(width: 36, height: 36)
                .background(Theme.raised, in: Circle())
                .foregroundStyle(Theme.ink)
        }
    }

    private func chip(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .foregroundStyle(Theme.ink)
                .background(Theme.raised, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var summaryTitle: String {
        if vm.mode == .hold {
            return vm.waypoints.first?.name ?? (vm.waypoints.isEmpty ? "Pick a spot" : "Spot picked")
        }
        guard vm.waypoints.count >= 2 else {
            return vm.waypoints.isEmpty ? "New route" : "Start set"
        }
        let miles = vm.routeLength / Units.metersPerMile
        let source = vm.isRouting ? "routing…" : (vm.plannedRoute?.source ?? "straight line")
        return String(format: "%.1f mi · %d points · %@", miles, vm.waypoints.count, source)
    }

    private var speedLabel: String {
        if let cap = vm.speedCapMph { return "Max \(Int(cap)) mph" }
        return "Road speed"
    }

    private var startTitle: String {
        switch vm.mode {
        case .hold: return "Teleport"
        default: return "Start \(vm.mode.displayName.lowercased())"
        }
    }

    // MARK: - Live

    private var livePanel: some View {
        let stats = vm.player.stats
        let state = vm.player.state

        return VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(stateTitle(state))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(stateColor(state))
                Spacer()
                if let problem = vm.player.problem {
                    Button {
                        AppModel.shared.showDoctor = true
                    } label: {
                        Label(problem.title, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.bad)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
            }

            if state == .holding {
                metric("Exact spot", label: "no GPS wander")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .bottom, spacing: 0) {
                    metric(String(format: "%.0f", stats.speedMph), label: "mph", large: true)
                    Spacer()
                    metric(formatMiles(stats.length - stats.distance), label: "left")
                    Spacer()
                    metric(formatDuration(stats.remaining), label: "eta")
                    Spacer()
                    metric("\(stats.stopsLeft)", label: "stops")
                }

                Slider(
                    value: Binding(get: { stats.progress }, set: { vm.player.seek(to: $0) }),
                    in: 0...1
                )
            }

            HStack(spacing: 10) {
                if state != .holding {
                    Button(action: vm.togglePause) {
                        Label(pauseTitle(state), systemImage: state.isMoving ? "pause.fill" : "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .foregroundStyle(Color.white.opacity(0.97))
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Button(action: vm.stop) {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .foregroundStyle(Theme.ink)
                        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if state == .holding {
                Text("Tap the map to jump somewhere else. Stop gives your real location back.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func metric(_ value: String, label: String, large: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(large ? .system(size: 44, weight: .bold, design: .rounded) : .system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private func stateTitle(_ state: PlaybackState) -> String {
        switch state {
        case .playing:  return "\(vm.mode.displayName.capitalized) in progress"
        case .waiting:  return String(format: "Waiting at a stop · %.0fs", vm.player.stats.dwellLeft)
        case .paused:   return "Paused, holding here"
        case .holding:  return "Teleported"
        case .finished: return "Arrived, holding at the end"
        case .idle:     return ""
        }
    }

    private func stateColor(_ state: PlaybackState) -> Color {
        switch state {
        case .playing, .holding: return Theme.good
        case .waiting, .paused:  return Theme.caution
        default:                 return Theme.ink
        }
    }

    private func pauseTitle(_ state: PlaybackState) -> String {
        switch state {
        case .finished: return "Again"
        case .paused:   return "Resume"
        default:        return "Pause"
        }
    }

    private func formatMiles(_ meters: Double) -> String {
        String(format: "%.1f mi", max(0, meters) / Units.metersPerMile)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        if total >= 3600 { return String(format: "%dh %02dm", total / 3600, (total % 3600) / 60) }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Options

struct OptionsSheet: View {
    @ObservedObject var vm: MapViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Use road speed", isOn: Binding(
                        get: { vm.speedCapMph == nil },
                        set: { vm.speedCapMph = $0 ? nil : Self.defaultCap(for: vm.mode) }
                    ))
                    if let cap = vm.speedCapMph {
                        Stepper(value: Binding(get: { cap }, set: { vm.speedCapMph = $0 }), in: 1...120, step: 1) {
                            HStack {
                                Text("Max speed")
                                Spacer()
                                Text("\(Int(cap)) mph").monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Speed")
                } footer: {
                    Text("Road speed follows each road's limit and slows for corners. A max speed is a ceiling, so you still slow down for turns.")
                }

                Section {
                    Toggle("Follow roads", isOn: $vm.followRoads)
                    Toggle("Stop at junctions and turns", isOn: $vm.stopsEnabled)
                    Toggle("GPS wander", isOn: $vm.wander)
                } header: {
                    Text("Realism")
                } footer: {
                    Text("Stops pause for a few seconds at some real intersections. GPS wander drifts the point a few metres the way a real phone's GPS does, so it never sits perfectly still.")
                }

                Section("Repeat") {
                    Toggle("Loop back to the start", isOn: $vm.loop)
                    Toggle("Go back and forth", isOn: $vm.pingPong)
                }
            }
            .navigationTitle("Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private static func defaultCap(for mode: TravelMode) -> Double {
        switch mode {
        case .drive: return 35
        case .bike: return 12
        case .walk, .hold: return 3
        }
    }
}
