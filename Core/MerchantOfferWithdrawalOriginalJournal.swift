import Foundation
import CryptoKit
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Historical roots are explicit, read-only inputs. Their records are NEVER migrated,
/// acknowledged or deleted here. Missing root provenance keeps compatibilityApproved false.
@MainActor public final class MerchantOfferWithdrawalOriginalJournal {
    private let store: MerchantOfferWithdrawalUnifiedStore
    private let historicalRoots: [URL]
    private let compatibilityApproved: () -> Bool
    public init(store: MerchantOfferWithdrawalUnifiedStore, historicalRoots: [URL] = [], compatibilityApproved: @escaping () -> Bool = { false }) {
        self.store = store; self.historicalRoots = historicalRoots; self.compatibilityApproved = compatibilityApproved
    }
    public var canBegin: Bool { compatibilityApproved() }
    /// Traverse the supplied root without following symlinks at ANY component. Pin
    /// descriptors before enumeration/reads so a path replacement cannot redirect us.
    /// This does not lock historical writers. They must remain an enablement blocker.
    private func openHistoricalDirectory(_ root: URL) throws -> Int32 {
        guard root.isFileURL, root.path.hasPrefix("/"),
              !root.pathComponents.contains(".."), !root.pathComponents.contains(".") else { throw MerchantOfferWithdrawalOriginalFailure.persistence }
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw MerchantOfferWithdrawalOriginalFailure.persistence }
        do {
            for component in root.pathComponents.dropFirst() {
                let next = openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
                guard next >= 0 else { throw MerchantOfferWithdrawalOriginalFailure.persistence }
                _ = close(fd); fd = next
            }
            return fd
        } catch { _ = close(fd); throw error }
    }
    private func historicalNames(_ fd: Int32) throws -> [String] {
        let copy = dup(fd)
        guard copy >= 0 else { throw MerchantOfferWithdrawalOriginalFailure.persistence }
        guard let stream = fdopendir(copy) else { _ = close(copy); throw MerchantOfferWithdrawalOriginalFailure.persistence }
        defer { _ = closedir(stream) }
        var names: [String] = []
        while true {
            errno = 0
            guard let entry = readdir(stream) else {
                guard errno == 0 else { throw MerchantOfferWithdrawalOriginalFailure.persistence }
                return names.sorted()
            }
            let name = withUnsafeBytes(of: entry.pointee.d_name) { raw in
                String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
            }
            if name == "." || name == ".." { continue }
            names.append(name)
            guard names.count <= 10000 else { throw MerchantOfferWithdrawalOriginalFailure.persistence }
        }
    }
    private func historicalBytes(_ name: String, directory: Int32) throws -> Data {
        let fd = openat(directory, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
        guard fd >= 0 else { throw MerchantOfferWithdrawalOriginalFailure.persistence }
        defer { _ = close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_nlink == 1, info.st_size > 0, info.st_size <= 16384 else { throw MerchantOfferWithdrawalOriginalFailure.persistence }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = buffer.withUnsafeMutableBytes { raw in
                #if canImport(Darwin)
                return Darwin.read(fd, raw.baseAddress, raw.count)
                #else
                return Glibc.read(fd, raw.baseAddress, raw.count)
                #endif
            }
            if n < 0 && errno == EINTR { continue }
            guard n >= 0 else { throw MerchantOfferWithdrawalOriginalFailure.persistence }
            if n == 0 { break }
            data.append(contentsOf: buffer.prefix(n))
            guard data.count <= 16384 else { throw MerchantOfferWithdrawalOriginalFailure.persistence }
        }
        guard data.count == Int(info.st_size) else { throw MerchantOfferWithdrawalOriginalFailure.persistence }
        return data
    }
    private func archived() throws -> [MerchantOfferWithdrawalOriginalPending] {
        var result: [MerchantOfferWithdrawalOriginalPending] = []
        for root in historicalRoots {
            // Missing/unreadable roots fail closed. Never create or reinterpret them as empty.
            let directory = try openHistoricalDirectory(root)
            defer { _ = close(directory) }
            for name in try historicalNames(directory) where name.hasSuffix(".json") {
                let data = try historicalBytes(name, directory: directory)
                guard let raw = String(data: data, encoding: .utf8) else { throw MerchantOfferWithdrawalOriginalFailure.persistence }
                _ = try ContentDraftJSON.parse(raw)
                let p = try JSONDecoder().decode(MerchantOfferWithdrawalOriginalPending.self, from: data); try p.validate()
                let identity = [String(p.accountID), String(p.merchantID), String(p.offerID), p.namespace, p.realm].map { "\($0.utf8.count):\($0)" }.joined()
                let expected = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined() + ".json"
                guard name == expected else { throw MerchantOfferWithdrawalOriginalFailure.persistence }
                result.append(p)
            }
        }
        return result
    }
    public func read(account: Int, merchant: Int, offer: Int, namespace: String, realm: String) throws -> MerchantOfferWithdrawalOriginalPending? {
        let old = try archived().filter { $0.accountID == account && $0.offerID == offer && $0.realm == realm }
        let current = try store.pending(account: account, merchant: merchant, offer: offer, namespace: namespace, realm: realm)
        guard old.count <= 1, old.first == nil || current == nil else { throw MerchantOfferWithdrawalOriginalFailure.persistence }
        if let p = old.first {
            guard p.merchantID == merchant, p.namespace == namespace else { throw MerchantOfferWithdrawalOriginalFailure.persistence }
            return p
        }
        if let current { return current }
        let key = "endpoint:" + Data(realm.utf8).base64EncodedString() + ":\(account):offer-\(offer)"
        guard try !store.contains(key) else { throw MerchantOfferWithdrawalOriginalFailure.unknown }
        return nil
    }
    public func entries(account: Int, merchant: Int, namespace: String, realm: String) throws -> [MerchantOfferWithdrawalOriginalPending] {
        let values = try archived().filter { $0.accountID == account && $0.merchantID == merchant && $0.namespace == namespace && $0.realm == realm }
            + store.entries(account: account, merchant: merchant, namespace: namespace, realm: realm)
        guard Set(values.map(\.offerID)).count == values.count else { throw MerchantOfferWithdrawalOriginalFailure.persistence }
        return values.sorted { $0.offerID < $1.offerID }
    }
    public func begin(_ p: MerchantOfferWithdrawalOriginalPending) throws {
        guard canBegin, try read(account: p.accountID, merchant: p.merchantID, offer: p.offerID, namespace: p.namespace, realm: p.realm) == nil else { throw MerchantOfferWithdrawalOriginalFailure.persistence }
        // The store rechecks BOTH old keys and commits UUID + resource atomically.
        // Historical roots are read-only; a running old writer remains an enablement blocker.
        guard canBegin else { throw MerchantOfferWithdrawalOriginalFailure.persistence }
        try store.begin(p)
    }
    public func canAcknowledge(_ p: MerchantOfferWithdrawalOriginalPending) throws -> Bool {
        guard try !archived().contains(where: { $0.accountID == p.accountID && $0.offerID == p.offerID && $0.realm == p.realm }) else { return false }
        return try store.pending(account: p.accountID, merchant: p.merchantID, offer: p.offerID,
                                 namespace: p.namespace, realm: p.realm) == p
    }
    public func acknowledge(_ p: MerchantOfferWithdrawalOriginalPending) throws {
        guard try !archived().contains(where: { $0.accountID == p.accountID && $0.offerID == p.offerID && $0.realm == p.realm }) else { throw MerchantOfferWithdrawalOriginalFailure.persistence }
        try store.acknowledge(p)
    }
}
