//
//  ConnectionProblem.swift
//  locspoof
//
//  Turns raw idevice / socket errors into: what happened, why, what to do.
//  The raw text is kept in `details` for the "Details" disclosure.
//

import Foundation

struct ConnectionProblem: Equatable, Identifiable {
    enum Kind: Equatable {
        case portClosed
        case noRoute
        case timedOut
        case pairingMissing
        case pairingRejected
        case portInUse
        case connectionReset
        case diskImage
        case unknown
    }

    let kind: Kind
    let title: String
    let explanation: String
    let steps: [String]
    let details: String

    var id: String { "\(kind)-\(details)" }

    /// Alert / sheet body: explanation, numbered steps, then the raw error.
    var message: String {
        let numbered = steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        return "\(explanation)\n\n\(numbered)\n\nDetails: \(details)"
    }

    static func from(error: NSError) -> ConnectionProblem {
        from(code: error.code, message: error.localizedDescription)
    }

    static func from(code: Int, message: String) -> ConnectionProblem {
        let lower = message.lowercased()
        let endpoint = DeviceConnectionContext.endpointDescription
        let details = "\(message) (code \(code), \(endpoint))"

        if lower.contains("refused") || lower.contains("os error 61") || code == 61 {
            return ConnectionProblem(
                kind: .portClosed,
                title: "Your iPhone refused the connection",
                explanation: "Nothing answered on port \(DeviceConnectionContext.remotePairingPort). The iPhone picks a new connection port each time it restarts, and locspoof couldn't find the new one.",
                steps: [
                    "Make sure LocalDevVPN is on (the VPN icon shows in the status bar).",
                    "Join a Wi-Fi network once. You can leave it after the tunnel connects.",
                    "Open Settings > Connection and tap Find Port.",
                    "Still refused? Make a new pairing file on the PC and import it."
                ],
                details: details
            )
        }

        if code == -17 || lower.contains("pairing file not found") {
            return ConnectionProblem(
                kind: .pairingMissing,
                title: "No pairing file",
                explanation: "locspoof needs a pairing file from your PC before it can talk to the iPhone.",
                steps: [
                    "On the PC, with the iPhone plugged in: python -m pymobiledevice3 lockdown remotepairing --pair",
                    "Send the pairing file to the iPhone (AirDrop, Files, or a chat).",
                    "Tap the file and open it in locspoof, or use Settings > Pairing File > Import."
                ],
                details: details
            )
        }

        if code == -9 || lower.contains("pair") && (lower.contains("invalid") || lower.contains("verify") || lower.contains("missing field")) {
            return ConnectionProblem(
                kind: .pairingRejected,
                title: "The iPhone rejected the pairing file",
                explanation: "The iPhone no longer trusts this pairing file. That happens after an iOS update, a reset of Location & Privacy, or re-pairing from another computer.",
                steps: [
                    "Make a fresh pairing file on the PC: python -m pymobiledevice3 lockdown remotepairing --pair",
                    "Import it in Settings > Pairing File > Replace."
                ],
                details: details
            )
        }

        if code == 54 || lower.contains("connection reset") {
            return ConnectionProblem(
                kind: .connectionReset,
                title: "The iPhone closed the connection",
                explanation: "The connection opened, then the iPhone dropped it during setup. This usually means it doesn't accept the pairing file anymore.",
                steps: [
                    "Turn LocalDevVPN off and on, then try again.",
                    "If it keeps happening, make a fresh pairing file on the PC and import it."
                ],
                details: details
            )
        }

        if code == 48 || lower.contains("address already in use") || lower.contains("port already in use") {
            return ConnectionProblem(
                kind: .portInUse,
                title: "Another app is holding the connection",
                explanation: "Another debugging, JIT or VPN app is using the developer tunnel.",
                steps: [
                    "Close StikDebug, RouteSim and similar apps.",
                    "Turn LocalDevVPN off and on.",
                    "If it persists, restart the iPhone (then locspoof finds the new port by itself)."
                ],
                details: details
            )
        }

        if lower.contains("unreachable") || lower.contains("no route") {
            return ConnectionProblem(
                kind: .noRoute,
                title: "LocalDevVPN isn't connected",
                explanation: "There's no route to \(DeviceConnectionContext.targetIPAddress). That address only exists while LocalDevVPN is on.",
                steps: [
                    "Open LocalDevVPN and connect it.",
                    "Check that its address is \(DeviceConnectionContext.defaultTargetIPAddress)."
                ],
                details: details
            )
        }

        if lower.contains("timed out") || lower.contains("timeout") {
            return ConnectionProblem(
                kind: .timedOut,
                title: "The iPhone didn't answer in time",
                explanation: "Usually LocalDevVPN is off, or the phone has never been on Wi-Fi since it restarted.",
                steps: [
                    "Turn on LocalDevVPN.",
                    "Join any Wi-Fi network once, then try again.",
                    "Unlock the iPhone."
                ],
                details: details
            )
        }

        if lower.contains("image") || lower.contains("ddi") || lower.contains("mount") {
            return ConnectionProblem(
                kind: .diskImage,
                title: "Developer disk image problem",
                explanation: "The developer disk image couldn't be mounted, so location simulation isn't available yet.",
                steps: [
                    "Check that Developer Mode is on: Settings > Privacy & Security > Developer Mode.",
                    "Make sure you have internet so locspoof can download the disk image.",
                    "Try again."
                ],
                details: details
            )
        }

        return ConnectionProblem(
            kind: .unknown,
            title: "Couldn't connect to the iPhone",
            explanation: "The developer tunnel couldn't be created.",
            steps: [
                "Turn LocalDevVPN off and on.",
                "Join Wi-Fi once, then try again.",
                "Run the checks in Settings > Connection > Run Checks to see which step fails."
            ],
            details: details
        )
    }
}
