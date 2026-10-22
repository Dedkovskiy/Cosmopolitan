import Foundation

// One repair at a time per bottle: an flock on <prefix>/.cosmo.lock. The kernel drops it when the holder dies, so there are no stale
// locks; the JSON inside only names the holder for the message. Opened with O_CLOEXEC: flock locks are shared by every copy of a
// descriptor, so a Wine process started while the lock is held would otherwise inherit a copy and keep the bottle locked after we exit.
final class PrefixLock {
    private let fd: Int32
    init?(_ prefix: String, purpose: String) {
        let fd = open(prefix + "/.cosmo.lock", O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
        guard fd >= 0 else { return nil }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); return nil }
        self.fd = fd
        let info = "{\"pid\":\(getpid()),\"purpose\":\"\(purpose)\",\"since\":\"\(ISO8601DateFormatter().string(from: Date()))\"}\n"
        ftruncate(fd, 0); _ = info.withCString { write(fd, $0, strlen($0)) }
    }
    deinit { flock(fd, LOCK_UN); close(fd) }
    static func holder(_ prefix: String) -> String { ((try? String(contentsOfFile: prefix + "/.cosmo.lock", encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
}
