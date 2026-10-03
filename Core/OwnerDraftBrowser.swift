import Foundation
import Observation

/// A bounded server-supplied display string, never interpreted as a local clock or entitlement.
/// Unsupported date encodings remain unavailable. Do not infer an epoch unit or timezone.
public struct ContentDraftServerTime: Codable, Equatable {
    public let display: String
    public init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        guard let text = try? box.decode(String.self), text.utf8.count <= 40,
              text.range(of: #"\A[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,3})?(Z|[+-][0-9]{2}:?[0-9]{2})?\z"#, options: .regularExpression) != nil else {
            throw DecodingError.dataCorruptedError(in: box, debugDescription: "Unsupported server timestamp")
        }
        display = text
    }
    public func encode(to encoder: Encoder) throws {
        var box = encoder.singleValueContainer()
        try box.encode(display)
    }
}

/// Sanitized metadata projection. Payloads, keys, device IDs and receipt rights never reach the view.
public struct OwnerDraftSummary: Equatable, Identifiable {
    public let id: Int64
    public let businessType: ContentDraftBusinessType
    public let version: Int64
    public let savedTime: String?
    public let installedReceipts: OwnerDraftInstalledReceipts?
    fileprivate let identity: ContentDraftIdentity
    init(_ record: ContentDraftRecord, owner: Int64, includeReceipts: Bool = false) throws {
        let identity = try ContentDraftIdentity(ownerMemberID: owner, businessType: record.businessType,
                                              clientDraftKey: record.clientDraftKey, scope: .personal)
        try record.validate(identity: identity)
        guard record.status == .draft else { throw ContentDraftIssue.malformed }
        self.identity = identity; id = record.id; businessType = record.businessType
        version = record.version; savedTime = record.updateTime?.display
        installedReceipts = includeReceipts ? OwnerDraftInstalledReceipts(record: record) : nil
    }
}

/// Owner-only read approval narrows W02's reviewed typed grant. No merchant delegation or writes.
public struct OwnerDraftReadApproval {
    public let grant: ContentDraftRouteGrant
    public init(grant: ContentDraftRouteGrant) throws {
        guard grant.scope == .personal, grant.ownerMemberID == Int64(grant.context.session.accountID),
              grant.routes == [.list, .restore] else { throw ContentDraftIssue.invalid }
        self.grant = grant
    }
    public func matches(_ context: RuntimeDependencyContext, now: Date = Date()) -> Bool {
        ContentDraftContextFence.matches(grant.context, context) && now < grant.expiresAt
    }
}

@available(macOS 14.0, *)
@MainActor @Observable public final class OwnerDraftBrowser {
    public enum Phase: String { case idle, loading, ready, empty, failed, invalidated }
    public private(set) var phase: Phase = .idle
    public private(set) var rows: [OwnerDraftSummary] = []
    public private(set) var detail: OwnerDraftSummary?
    public private(set) var detailLoading = false
    public private(set) var issue: ContentDraftIssue?
    public private(set) var detailIssue: ContentDraftIssue?
    public let identity = UUID()
    private let reader: any ContentDraftReading
    private let lease: ContentDraftSessionLease
    private let owner: Int64
    private var listGeneration = UUID()
    private var detailGeneration = UUID()
    public init(reader: any ContentDraftReading, lease: ContentDraftSessionLease) {
        self.reader = reader; self.lease = lease; owner = Int64(lease.context.session.accountID)
    }
    public func invalidate() {
        lease.revoke(); listGeneration = UUID(); detailGeneration = UUID()
        rows = []; detail = nil; detailLoading = false; issue = .staleSession
        detailIssue = .staleSession; phase = .invalidated
    }
    private func current() -> Bool {
        guard lease.isCurrent else { invalidate(); return false }; return phase != .invalidated
    }
    public func load() async {
        guard !Task.isCancelled, current(), phase != .loading else { return }
        let ticket = UUID(); listGeneration = ticket
        // Clear prior content during refresh; a failure cannot leave stale data looking current.
        closeDetail(); rows = []; phase = .loading; issue = nil
        do {
            let records = try await reader.list(type: nil)
            guard current(), listGeneration == ticket else { return }
            guard !Task.isCancelled else { closeList(); return }
            var seen = Set<Int64>()
            let summaries = try records.map { record -> OwnerDraftSummary in
                guard seen.insert(record.id).inserted else { throw ContentDraftIssue.malformed }
                return try OwnerDraftSummary(record, owner: owner)
            }
            rows = summaries; phase = rows.isEmpty ? .empty : .ready
        } catch {
            guard current(), listGeneration == ticket else { return }
            guard !Task.isCancelled else { closeList(); return }
            issue = (error as? ContentDraftIssue) ?? .unavailable; phase = .failed
        }
    }
    public func restore(id: Int64) async {
        guard !Task.isCancelled, current(), phase == .ready, let row = rows.first(where: { $0.id == id }) else { return }
        let ticket = UUID(); detailGeneration = ticket; detail = nil; detailIssue = nil; detailLoading = true
        do {
            let record = try await reader.restore(id: id, identity: row.identity)
            guard current(), detailGeneration == ticket else { return }
            guard !Task.isCancelled else { closeDetail(); return }
            try record.validate(identity: row.identity)
            guard record.id == id, record.version >= row.version else { throw ContentDraftIssue.malformed }
            detail = try OwnerDraftSummary(record, owner: owner, includeReceipts: true); detailLoading = false
        } catch {
            guard current(), detailGeneration == ticket else { return }
            guard !Task.isCancelled else { closeDetail(); return }
            detailIssue = (error as? ContentDraftIssue) ?? .unavailable; detailLoading = false
        }
    }
    /// End the list's display lifetime without revoking its session. Reopening may start a
    /// fresh read even when a cancelled transport has not completed the retired read yet.
    /// A push to detail is not a list dismissal: it still needs the validated owner row.
    public func closeList() {
        guard phase != .invalidated else { return }
        listGeneration = UUID(); closeDetail(); rows = []; issue = nil; phase = .idle
    }
    /// Back/close cancels the display lifetime, including a restore that completes after dismissal.
    public func closeDetail() {
        detailGeneration = UUID(); detail = nil; detailIssue = nil; detailLoading = false
    }
}
