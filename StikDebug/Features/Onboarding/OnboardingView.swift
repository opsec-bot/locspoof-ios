import SwiftUI

struct OnboardingView: View {
    var onComplete: () -> Void

    @State private var step: Step = .welcome
    @State private var pairingReady = PairingFileStore.exists
    @State private var showPicker = false
    @State private var importError: String?

    enum Step: Int, CaseIterable {
        case welcome, pairing, vpn, developerMode, done
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                content
                Spacer()
                buttons
                dots
            }
            .padding(24)
            .background(Theme.panel.ignoresSafeArea())
            .navigationTitle("Set up locspoof")
            .navigationBarTitleDisplayMode(.inline)
        }
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: PairingFileStore.supportedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            do {
                try PairingFileStore.importFile(at: url)
                pairingReady = true
                importError = nil
            } catch {
                importError = error.localizedDescription
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pairingFileImported)) { _ in
            pairingReady = true
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            StepCard(
                icon: "location.fill",
                title: "locspoof",
                message: "Set your iPhone's location anywhere, or drive, bike or walk a real route with real speeds, stops at junctions and natural GPS drift."
            )

        case .pairing:
            VStack(spacing: 16) {
                StepCard(
                    icon: "key.fill",
                    title: "Pairing file",
                    message: "Plug the iPhone into your PC and run:\n**python -m pymobiledevice3 lockdown remotepairing --pair**\nSend the file it makes to this phone, then import it here. You can replace it later in Settings."
                )
                if pairingReady {
                    Label("Pairing file imported", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.good)
                    Button("Replace") { showPicker = true }
                        .buttonStyle(.bordered)
                } else {
                    Button("Import pairing file") { showPicker = true }
                        .buttonStyle(.borderedProminent)
                }
                if let importError {
                    Text(importError)
                        .font(.footnote)
                        .foregroundStyle(Theme.bad)
                        .multilineTextAlignment(.center)
                }
            }

        case .vpn:
            StepCard(
                icon: "network",
                title: "LocalDevVPN",
                message: "Install **LocalDevVPN** from the App Store and turn it on. It lets locspoof reach the iPhone's own developer services, even off Wi-Fi once connected."
            )

        case .developerMode:
            StepCard(
                icon: "hammer.fill",
                title: "Developer Mode",
                message: "**Settings > Privacy & Security > Developer Mode**, turn it on and restart. locspoof finds the iPhone's new connection port by itself after every restart."
            )

        case .done:
            StepCard(
                icon: "checkmark.circle.fill",
                title: "Ready",
                message: "Tap the map to set a start and a destination, pick Drive, Bike or Walk, and press Start. Or pick Teleport to jump to one spot."
            )
        }
    }

    private var buttons: some View {
        HStack {
            if step != .welcome {
                Button("Back") {
                    withAnimation { step = Step(rawValue: step.rawValue - 1) ?? .welcome }
                }
                .buttonStyle(.bordered)
            }
            Spacer()
            Button(step == .done ? "Start" : "Next") {
                if step == .done {
                    onComplete()
                } else {
                    withAnimation { step = Step(rawValue: step.rawValue + 1) ?? .done }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(step == .pairing && !pairingReady)
        }
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.rawValue) { s in
                Circle()
                    .fill(s == step ? Theme.accent : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
    }
}

private struct StepCard: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundStyle(Theme.accent)
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(Theme.ink)
            Text((try? AttributedString(
                markdown: message,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )) ?? AttributedString(message))
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }
}
