import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// The existing string-array file remains the authority. A UUID marker and its legacy
/// resource key are committed in ONE durable replacement. Only cooperating versions
/// use the sidecar flock; this does not certify older processes or unknown journal roots.
@MainActor public final class MerchantOfferWithdrawalUnifiedStore: CoopFlowLockStore {
    private let url: URL
    private var directory: URL { url.deletingLastPathComponent() }
    private let prefix = "offer-original-v1:"
    public init(url: URL) { self.url = url }
    private func legacy(_ key: String) -> String {
        guard key.hasPrefix("endpoint:") else { return key }
        return key.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false).dropFirst(2).joined(separator: ":")
    }
    private func resource(_ p: MerchantOfferWithdrawalOriginalPending) -> String { "\(p.accountID):offer-\(p.offerID)" }
    private func scoped(_ p: MerchantOfferWithdrawalOriginalPending) -> String {
        "endpoint:" + Data(p.realm.utf8).base64EncodedString() + ":" + resource(p)
    }
    private func marker(_ p: MerchantOfferWithdrawalOriginalPending) throws -> String {
        prefix + (try JSONEncoder().encode(p)).base64EncodedString()
    }
    private func originals(_ keys: Set<String>) throws -> [(String, MerchantOfferWithdrawalOriginalPending)] {
        try keys.filter { $0.hasPrefix(prefix) }.map { key in
            guard let data = Data(base64Encoded: String(key.dropFirst(prefix.count))) else { throw CoopFlowFailure.storage }
            let p = try JSONDecoder().decode(MerchantOfferWithdrawalOriginalPending.self, from: data)
            try p.validate(); return (key, p)
        }
    }
    private func conflicts(_ key: String, keys: Set<String>) throws -> Bool {
        let old = legacy(key)
        if keys.contains(old) || keys.contains(key) { return true }
        if key == old && keys.contains(where: { $0.hasPrefix("endpoint:") && legacy($0) == old }) { return true }
        return try originals(keys).contains { _, p in
            resource(p) == old && (key == old || scoped(p) == key)
        }
    }
    public func contains(_ key: String) throws -> Bool { try locked { try conflicts(key, keys: load()) } }
    public func acquire(_ key: String) throws {
        try locked {
            var keys = try load()
            guard !key.isEmpty, !key.hasPrefix(prefix), try !conflicts(key, keys: keys) else { throw CoopFlowFailure.ambiguous }
            keys.insert(key); try commit(keys)
        }
    }
    public func complete(_ key: String) throws {
        try locked {
            var keys = try load()
            // A legacy completion is never authority to acknowledge an original UUID.
            guard try !originals(keys).contains(where: { _, p in scoped(p) == key || resource(p) == key }) else { throw CoopFlowFailure.ambiguous }
            keys.remove(key); try commit(keys)
        }
    }
    public func pending(account: Int, merchant: Int, offer: Int, namespace: String, realm: String) throws -> MerchantOfferWithdrawalOriginalPending? {
        try locked {
            let all = try originals(load()).map { $0.1 }.filter { $0.accountID == account && $0.offerID == offer && $0.realm == realm }
            guard all.count <= 1 else { throw CoopFlowFailure.storage }
            guard let p = all.first else { return nil }
            guard p.merchantID == merchant, p.namespace == namespace else { throw CoopFlowFailure.ambiguous }
            return p
        }
    }
    public func entries(account: Int, merchant: Int, namespace: String, realm: String) throws -> [MerchantOfferWithdrawalOriginalPending] {
        try locked { try originals(load()).map { $0.1 }.filter { $0.accountID == account && $0.merchantID == merchant && $0.namespace == namespace && $0.realm == realm }.sorted { $0.offerID < $1.offerID } }
    }
    public func begin(_ p: MerchantOfferWithdrawalOriginalPending) throws {
        try p.validate()
        try locked {
            var keys = try load()
            guard try !conflicts(scoped(p), keys: keys) else { throw CoopFlowFailure.ambiguous }
            keys.insert(scoped(p)); keys.insert(try marker(p)); try commit(keys)
        }
    }
    public func acknowledge(_ p: MerchantOfferWithdrawalOriginalPending) throws {
        try p.validate()
        try locked {
            var keys = try load()
            let held = try originals(keys).filter { $0.1.accountID == p.accountID && $0.1.offerID == p.offerID && $0.1.realm == p.realm }
            guard held.count == 1, held[0].1 == p, keys.contains(scoped(p)), !keys.contains(resource(p)) else { throw CoopFlowFailure.ambiguous }
            keys.remove(held[0].0); keys.remove(scoped(p)); try commit(keys)
        }
    }
    private func load() throws -> Set<String> {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        if fd < 0 { guard errno == ENOENT else { throw CoopFlowFailure.storage }; return [] }
        defer { _ = close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), info.st_size > 0, info.st_size <= 1048576 else { throw CoopFlowFailure.storage }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if n < 0 && errno == EINTR { continue }
            guard n >= 0 else { throw CoopFlowFailure.storage }
            if n == 0 { break }
            data.append(contentsOf: buffer.prefix(n)); guard data.count <= 1048576 else { throw CoopFlowFailure.storage }
        }
        let rows = try JSONDecoder().decode([String].self, from: data)
        guard rows.count == Set(rows).count else { throw CoopFlowFailure.storage }
        let keys = Set(rows)
        guard !keys.contains(where: { $0.hasPrefix("offer-original-") && !$0.hasPrefix(prefix) }) else { throw CoopFlowFailure.storage }
        let pending = try originals(keys)
        guard pending.allSatisfy({ keys.contains(scoped($0.1)) }),
              Set(pending.map { scoped($0.1) }).count == pending.count else { throw CoopFlowFailure.storage }
        return keys
    }
    private func locked<T>(_ body: () throws -> T) throws -> T {
        guard url.isFileURL else { throw CoopFlowFailure.storage }
        try ensureDirectory(directory)
        let fd = open(url.appendingPathExtension("lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else { throw CoopFlowFailure.storage }
        defer { _ = flock(fd, LOCK_UN); _ = close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw CoopFlowFailure.storage }
        return try body()
    }
    private func ensureDirectory(_ path: URL) throws {
        var info = stat()
        if lstat(path.path, &info) == 0 {
            guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { throw CoopFlowFailure.storage }
            // Inspect ancestors as well: O_NOFOLLOW on the leaf cannot reject a parent symlink.
            if path.path != "/" { try ensureDirectory(path.deletingLastPathComponent()) }
            return
        }
        guard errno == ENOENT, path.path != "/" else { throw CoopFlowFailure.storage }
        try ensureDirectory(path.deletingLastPathComponent())
        guard mkdir(path.path, mode_t(0o700)) == 0 || errno == EEXIST else { throw CoopFlowFailure.storage }
        try ensureDirectory(path); try syncDirectory(path.deletingLastPathComponent())
    }
    private func syncDirectory(_ path: URL) throws {
        let fd = open(path.path, O_RDONLY | O_NOFOLLOW); guard fd >= 0 else { throw CoopFlowFailure.storage }
        defer { _ = close(fd) }
        guard fsync(fd) == 0 else { throw CoopFlowFailure.storage }
    }
    private func commit(_ keys: Set<String>) throws {
        let bytes = try JSONEncoder().encode(keys.sorted()); guard bytes.count <= 1048576 else { throw CoopFlowFailure.storage }
        let temporary = directory.appendingPathComponent(".offer-pending-" + UUID().uuidString)
        let fd = open(temporary.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else { throw CoopFlowFailure.storage }
        defer { _ = close(fd); _ = unlink(temporary.path) }
        try bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { throw CoopFlowFailure.storage }
            var written = 0
            while written < raw.count {
                #if canImport(Darwin)
                let n = Darwin.write(fd, base.advanced(by: written), raw.count - written)
                #else
                let n = Glibc.write(fd, base.advanced(by: written), raw.count - written)
                #endif
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw CoopFlowFailure.storage }; written += n
            }
        }
        guard fsync(fd) == 0 else { throw CoopFlowFailure.storage }
        #if canImport(Darwin)
        guard fcntl(fd, F_FULLFSYNC) == 0 else { throw CoopFlowFailure.storage }
        #endif
        guard rename(temporary.path, url.path) == 0 else { throw CoopFlowFailure.storage }
        try syncDirectory(directory)
    }
}
