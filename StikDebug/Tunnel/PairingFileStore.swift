//
//  PairingFileStore.swift
//  locspoof
//

import Foundation
import UniformTypeIdentifiers

enum PairingFileError: LocalizedError {
    case unreadable
    case notAPlist
    case lockdownRecord
    case missingKeys([String])

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "locspoof couldn't read that file."
        case .notAPlist:
            return "That isn't a pairing file. Pick the .plist or .mobiledevicepairing file made on the PC."
        case .lockdownRecord:
            return "This is a lockdown pairing record (the kind RouteLocation uses). locspoof needs the RemotePairing kind. On the PC run: python -m pymobiledevice3 lockdown remotepairing --pair, then send the file it makes."
        case .missingKeys(let keys):
            return "This pairing file is missing \(keys.joined(separator: ", ")). Make a new one on the PC with: python -m pymobiledevice3 lockdown remotepairing --pair"
        }
    }
}

struct PairingInfo {
    let identifier: String
    let importedAt: Date?
}

enum PairingFileStore {
    static let fileName = "rp_pairing_file.plist"

    /// .plist, .mobiledevicepairing and .mobiledevicepair. The last two are
    /// declared in Info.plist (UTImportedTypeDeclarations); without that
    /// declaration the picker greys them out.
    static let supportedContentTypes: [UTType] = [
        UTType("app.locspoof.mobiledevicepairing"),
        UTType(filenameExtension: "mobiledevicepairing"),
        UTType(filenameExtension: "mobiledevicepair"),
        UTType.propertyList,
        UTType.xml,
        UTType.data
    ].compactMap { $0 }

    static let fileExtensions: Set<String> = ["plist", "mobiledevicepairing", "mobiledevicepair"]

    private static let legacyFileName = "pairingFile.plist"
    private static let requiredKeys = ["identifier", "private_key", "public_key"]

    static var url: URL {
        directoryURL.appendingPathComponent(fileName)
    }

    static var exists: Bool {
        FileManager.default.fileExists(atPath: prepareURL().path)
    }

    static var info: PairingInfo? {
        guard let data = try? Data(contentsOf: prepareURL()),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let identifier = dict["identifier"] as? String else {
            return nil
        }
        return PairingInfo(
            identifier: identifier,
            importedAt: UserDefaults.standard.object(forKey: UserDefaults.Keys.pairingImportedAt) as? Date
        )
    }

    @discardableResult
    static func prepareURL(fileManager: FileManager = .default) -> URL {
        let destination = url
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        guard !fileManager.fileExists(atPath: destination.path) else {
            removeLegacyCopies(fileManager: fileManager)
            return destination
        }

        migrateLegacyCopy(to: destination, fileManager: fileManager)
        return destination
    }

    /// Checks the file is a RemotePairing record before anything is replaced,
    /// so a wrong file never overwrites a working one.
    static func validate(_ data: Data) throws {
        guard !data.isEmpty else { throw PairingFileError.unreadable }
        guard let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw PairingFileError.notAPlist
        }
        let missing = requiredKeys.filter { dict[$0] == nil }
        if missing.isEmpty { return }
        if dict["HostCertificate"] != nil || dict["DeviceCertificate"] != nil {
            throw PairingFileError.lockdownRecord
        }
        throw PairingFileError.missingKeys(missing)
    }

    /// Imports a picked or opened file, replacing any existing one, then
    /// reconnects with it. No reinstall needed.
    static func importFile(at sourceURL: URL, fileManager: FileManager = .default) throws {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing { sourceURL.stopAccessingSecurityScopedResource() }
        }

        guard let data = try? Data(contentsOf: sourceURL) else {
            throw PairingFileError.unreadable
        }
        try validate(data)

        let destination = prepareURL(fileManager: fileManager)
        try data.write(to: destination, options: .atomic)
        removeLegacyCopies(fileManager: fileManager)
        protectPairingFile(at: destination, fileManager: fileManager)
        UserDefaults.standard.set(Date(), forKey: UserDefaults.Keys.pairingImportedAt)
        LogManager.shared.addInfoLog("Imported pairing file \(sourceURL.lastPathComponent)")

        NotificationCenter.default.post(name: .pairingFileImported, object: nil)
    }

    static func remove(fileManager: FileManager = .default) throws {
        let destination = prepareURL(fileManager: fileManager)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        removeLegacyCopies(fileManager: fileManager)
        UserDefaults.standard.removeObject(forKey: UserDefaults.Keys.pairingImportedAt)
    }

    private static var directoryURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pairing", isDirectory: true)
    }

    private static var legacyURLs: [URL] {
        [
            URL.documentsDirectory.appendingPathComponent(fileName),
            URL.documentsDirectory.appendingPathComponent(legacyFileName)
        ]
    }

    private static func migrateLegacyCopy(to destination: URL, fileManager: FileManager) {
        for legacyURL in legacyURLs where fileManager.fileExists(atPath: legacyURL.path) {
            do {
                try fileManager.moveItem(at: legacyURL, to: destination)
            } catch {
                if let data = try? Data(contentsOf: legacyURL) {
                    try? data.write(to: destination, options: .atomic)
                    try? fileManager.removeItem(at: legacyURL)
                }
            }

            protectPairingFile(at: destination, fileManager: fileManager)
            break
        }
    }

    private static func removeLegacyCopies(fileManager: FileManager) {
        for legacyURL in legacyURLs where fileManager.fileExists(atPath: legacyURL.path) {
            try? fileManager.removeItem(at: legacyURL)
        }
    }

    private static func protectPairingFile(at url: URL, fileManager: FileManager) {
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
