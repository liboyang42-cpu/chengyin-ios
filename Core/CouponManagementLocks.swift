import Foundation
import CryptoKit

public struct CouponManagementPending: Codable, Equatable {
    public let operationID: UUID
    public let ownerKey: String
    public let resource: String
    public let request: CouponManagementRequest
    public let createdAt: Date
    /// Exact wire payload, never headers or credentials. Optional for backward decoding.
    public var wire: CouponManagementWire? = nil
}
@MainActor public protocol CouponManagementLocking: AnyObject {
    func pending(ownerKey: String, resource: String) throws -> CouponManagementPending?
    /// Must atomically fail if another coordinator/process already holds this resource.
    func acquire(_ pending: CouponManagementPending) throws
    func release(_ pending: CouponManagementPending) throws
}
/// Durable, cross-epoch write-ahead record. An unreadable/corrupt existing record fails closed.
/// No automatic timeout/TTL or retry clearing; no source operation-receipt route exists.
@MainActor public final class CouponManagementFileLocks: CouponManagementLocking {
    private let directory: URL
    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    private func url(_ owner: String, _ resource: String) -> URL {
        let raw = "\(owner.utf8.count):\(owner):\(resource)"
        // A deployment namespace can exceed filesystem component limits; hash only the filename.
        // The full owner/resource identity is retained and verified inside the record.
        let name = SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name + ".json")
    }
    public func pending(ownerKey: String, resource: String) throws -> CouponManagementPending? {
        let path = url(ownerKey, resource)
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        let value = try JSONDecoder().decode(CouponManagementPending.self, from: Data(contentsOf: path))
        guard value.ownerKey == ownerKey, value.resource == resource else { throw CouponManagementError.storage }
        return value
    }
    public func acquire(_ pending: CouponManagementPending) throws {
        // Exclusive creation, unlike check-then-replace atomic writes. If interrupted while writing,
        // the leftover partial file is a hard lock, not permission to dispatch again.
        try JSONEncoder().encode(pending).write(to: url(pending.ownerKey, pending.resource), options: [.withoutOverwriting])
    }
    public func release(_ pending: CouponManagementPending) throws {
        guard try self.pending(ownerKey: pending.ownerKey, resource: pending.resource) == pending else { throw CouponManagementError.storage }
        try FileManager.default.removeItem(at: url(pending.ownerKey, pending.resource))
    }
}
