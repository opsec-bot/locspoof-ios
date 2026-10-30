//
//  mountDDI.swift
//  StikDebug
//
//  Created by Stossy11 on 29/03/2025.
//

import Foundation

typealias RpPairingFileHandle = OpaquePointer
typealias AdapterHandle = OpaquePointer
typealias RsdHandshakeHandle = OpaquePointer
typealias ImageMounterHandle = OpaquePointer
typealias LockdowndClientHandle = OpaquePointer

func progressCallback(progress: size_t, total: size_t, context: UnsafeMutableRawPointer?) {
    MountingProgress.shared.progressCallback(progress: progress, total: total, context: context)
}

enum MountCheckResult {
    case mounted
    case notMounted
    case unreachable
}

/// From iOS 27 the developer disk image has to be the Cryptex variant, installed
/// over cryptexd. The app's bundled library can't do that, and the Personalized
/// image it can mount has no build identity for those devices (BadBuildManifest).
/// So locspoof Setup installs it from a computer, and the app doesn't try.
/// Same cutoff as pymobiledevice3 (CRYPTEX_IMAGE_MIN_VERSION).
let setupInstallsDiskImage = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27

func isMounted() -> Bool {
    return checkMountStatus() == .mounted
}

func checkMountStatus() -> MountCheckResult {
    do {
        let result = try JITEnableContext.shared.getMountedDeviceCount()
        return result > 0 ? .mounted : .notMounted
    } catch {
        return .unreachable
    }
}

func mountPersonalDDI(imagePath: String, trustcachePath: String, manifestPath: String) -> String? {
    do {
        try JITEnableContext.shared.mountPersonalDDI(withImagePath: imagePath, trustcachePath: trustcachePath, manifestPath: manifestPath)
    } catch {
        LogManager.shared.addErrorLog("Failed to mount DDI: \(error.localizedDescription)")
        return error.localizedDescription
    }
    return nil
}
