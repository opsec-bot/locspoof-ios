import Foundation

extension UserDefaults {
    enum Keys {
        static let targetDeviceIP = "TunnelDeviceIP"
        static let remotePairingPort = "RemotePairingPort"
        static let autoFindPort = "AutoFindPort"
        static let pairingImportedAt = "PairingImportedAt"
        static let gpsWander = "GpsWander"
        static let stopsEnabled = "StopsEnabled"
        static let followRoads = "FollowRoads"
    }
}
