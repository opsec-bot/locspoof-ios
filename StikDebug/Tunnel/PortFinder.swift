//
//  PortFinder.swift
//  locspoof
//
//  iOS chooses the RemotePairing port when it boots, so the port that worked
//  yesterday can be closed today. When that happens every connection gets
//  "Connection refused (os error 61)". This finds the current one.
//
//  Two steps. First a fast scan for open TCP ports: through LocalDevVPN the
//  target is the phone itself, so closed ports refuse instantly. Then each open
//  port gets an RPPairing hello. Only the RemotePairing service answers with
//  the "RPPairing" magic, so other open services are never mistaken for it,
//  and nothing here can hang the way a full tunnel attempt on the wrong port can.
//

import Darwin
import Foundation

enum PortFinder {
    static let scanRange: ClosedRange<UInt16> = 49152...65535

    private static let magic = Array("RPPairing".utf8)

    /// A plain RemotePairing handshake request, the same first message
    /// pymobiledevice3 sends. Framed as "RPPairing" + big-endian UInt16 length + JSON.
    private static let helloPacket: [UInt8] = {
        let body = Array(#"{"message":{"plain":{"_0":{"request":{"_0":{"handshake":{"_0":{"hostOptions":{"attemptPairVerify":true},"wireProtocolVersion":19}}}}}}},"originatedBy":"host","sequenceNumber":0}"#.utf8)
        return PortFinder.magic + [UInt8(body.count >> 8), UInt8(body.count & 0xFF)] + body
    }()

    /// Finds the RemotePairing port. Tries the saved port and 49152 first, then scans.
    /// Blocking; call off the main thread.
    static func find(host: String, progress: ((Double) -> Void)? = nil) -> UInt16? {
        var tried = Set<UInt16>()
        for guess in [DeviceConnectionContext.remotePairingPort, DeviceConnectionContext.defaultPort] where !tried.contains(guess) {
            tried.insert(guess)
            if speaksRemotePairing(host: host, port: guess) {
                return guess
            }
        }

        let open = openPorts(host: host, range: scanRange, progress: progress)
        LogManager.shared.addInfoLog("Port scan found open ports: \(open)")
        for port in open where !tried.contains(port) {
            if speaksRemotePairing(host: host, port: port) {
                LogManager.shared.addInfoLog("RemotePairing answered on port \(port)")
                return port
            }
        }
        return nil
    }

    /// True if `port` answers an RPPairing hello with RPPairing framing.
    static func speaksRemotePairing(host: String, port: UInt16, timeout: TimeInterval = 2) -> Bool {
        guard let address = makeAddress(host: host, port: port) else { return false }
        let fd = beginConnect(address)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }

        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        guard Darwin.poll(&pfd, 1, Int32(timeout * 1000)) == 1, socketError(fd) == 0 else {
            return false
        }

        // Back to blocking with timeouts for the short exchange.
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags & ~O_NONBLOCK)
        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let sent = helloPacket.withUnsafeBytes { Darwin.send(fd, $0.baseAddress, $0.count, 0) }
        guard sent == helloPacket.count else { return false }

        var reply = [UInt8](repeating: 0, count: magic.count)
        var received = 0
        while received < reply.count {
            let n = reply.withUnsafeMutableBytes { buffer in
                Darwin.recv(fd, buffer.baseAddress! + received, buffer.count - received, 0)
            }
            if n <= 0 { return false }
            received += n
        }
        return reply == magic
    }

    /// Ports in `range` that accept a TCP connection.
    static func openPorts(
        host: String,
        range: ClosedRange<UInt16>,
        batchSize: Int = 128,
        timeout: TimeInterval = 0.4,
        progress: ((Double) -> Void)? = nil
    ) -> [UInt16] {
        var open: [UInt16] = []
        let all = Array(range)
        var index = 0

        while index < all.count {
            let batch = all[index..<min(index + batchSize, all.count)]
            index += batch.count

            var fds: [pollfd] = []
            var ports: [UInt16] = []
            for port in batch {
                guard let address = makeAddress(host: host, port: port) else { continue }
                let fd = beginConnect(address)
                if fd >= 0 {
                    fds.append(pollfd(fd: fd, events: Int16(POLLOUT), revents: 0))
                    ports.append(port)
                }
            }

            let deadline = Date().addingTimeInterval(timeout)
            var pending = fds.count
            while pending > 0 {
                let remaining = Int32(deadline.timeIntervalSinceNow * 1000)
                if remaining <= 0 { break }
                if Darwin.poll(&fds, nfds_t(fds.count), remaining) <= 0 { break }
                for i in fds.indices where fds[i].fd >= 0 && fds[i].revents != 0 {
                    if fds[i].revents & Int16(POLLOUT) != 0, socketError(fds[i].fd) == 0 {
                        open.append(ports[i])
                    }
                    Darwin.close(fds[i].fd)
                    // poll() skips negative descriptors.
                    fds[i].fd = -1
                    pending -= 1
                }
            }
            for entry in fds where entry.fd >= 0 {
                Darwin.close(entry.fd)
            }

            progress?(Double(index) / Double(all.count))
        }
        return open
    }

    // MARK: - Socket helpers

    private static func makeAddress(host: String, port: UInt16) -> sockaddr_in? {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard host.withCString({ inet_pton(AF_INET, $0, &address.sin_addr) }) == 1 else {
            return nil
        }
        return address
    }

    /// Starts a non-blocking connect. Returns the descriptor, or -1.
    private static func beginConnect(_ address: sockaddr_in) -> Int32 {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }

        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        var target = address
        let result = withUnsafePointer(to: &target) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if result == 0 || errno == EINPROGRESS {
            return fd
        }
        Darwin.close(fd)
        return -1
    }

    private static func socketError(_ fd: Int32) -> Int32 {
        var error: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) == 0 else { return errno }
        return error
    }
}
