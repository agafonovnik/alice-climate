import Foundation
import Darwin

/// The kernel releases this per-user lock when its owner exits, including crashes.
/// Keep the file in place: unlinking a locked file could allow two different inodes to be locked.
public final class SingleInstanceGate {
    private let descriptor: Int32
    public let isPrimary: Bool

    public init(path: String) throws {
        let fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), (info.st_mode & S_IFMT) == S_IFREG else {
            close(fd)
            throw POSIXError(.EPERM)
        }
        let primary: Bool
        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            primary = true
        } else {
            let code = errno
            guard code == EWOULDBLOCK || code == EAGAIN else {
                close(fd)
                throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
            }
            primary = false
        }
        descriptor = fd
        isPrimary = primary
        if primary { try writeState(ready: false) }
    }

    deinit { close(descriptor) }

    public func markReady() throws {
        guard isPrimary else { return }
        try writeState(ready: true)
    }

    public var ownerPID: Int32? { state?.0 }
    public var ownerIsReady: Bool { state?.1 == true }

    private var state: (Int32, Bool)? {
        var bytes = [UInt8](repeating: 0, count: 128)
        let count = pread(descriptor, &bytes, bytes.count, 0)
        guard count > 0, let text = String(bytes: bytes.prefix(count), encoding: .utf8) else { return nil }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let pid = Int32(parts[0]), pid > 0 else { return nil }
        return (pid, parts[1] == "ready\n")
    }

    private func writeState(ready: Bool) throws {
        let bytes = Array("\(getpid()):\(ready ? "ready" : "starting")\n".utf8)
        guard ftruncate(descriptor, 0) == 0, pwrite(descriptor, bytes, bytes.count, 0) == bytes.count else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
