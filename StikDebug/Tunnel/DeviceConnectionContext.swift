//
//  DeviceConnectionContext.swift
//  locspoof
//

import Foundation

enum DeviceConnectionContext {
    static let defaultTargetIPAddress = "10.7.0.1"
    /// iOS picks the RemotePairing port when it boots. 49152 is only the usual
    /// first pick, so it is a starting guess, never an assumption.
    static let defaultPort: UInt16 = 49152

    static var targetIPAddress: String {
        let stored = UserDefaults.standard
            .string(forKey: UserDefaults.Keys.targetDeviceIP)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let stored, !stored.isEmpty else {
            return defaultTargetIPAddress
        }
        return stored
    }

    static var remotePairingPort: UInt16 {
        get {
            let stored = UserDefaults.standard.integer(forKey: UserDefaults.Keys.remotePairingPort)
            return (1...65535).contains(stored) ? UInt16(stored) : defaultPort
        }
        set {
            UserDefaults.standard.set(Int(newValue), forKey: UserDefaults.Keys.remotePairingPort)
        }
    }

    static var autoFindPort: Bool {
        UserDefaults.standard.object(forKey: UserDefaults.Keys.autoFindPort) as? Bool ?? true
    }

    static var endpointDescription: String {
        "\(targetIPAddress):\(remotePairingPort)"
    }
}
