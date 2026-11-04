import Foundation
import CoreFoundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor @Observable public final class NativeChannelAuditFlow {
    public enum Source: Equatable { case governance, lifecycle }
    public let source: Source
    public struct OperationRow: Identifiable, Equatable {
        public let id: String
        public let channelID: String
        public let action: String
        public let fromStatus: Int?
        public let toStatus: Int?
        public let operatorID: String?
        public let requestID: String?
        public let reason: String?
        public let createdAt: String
    }
    private var storedOperations: [OperationRow] = []
    public var operations: [OperationRow] { isCurrent ? storedOperations : [] }

    public struct Row: Identifiable, Equatable {
        public let id: String
        public let channelID: String
        public let actorType: String
        public let actorID: String?
        public let action: String
        public let targetType: String
        public let targetID: String?
        public let reason: String?
        public let createdAt: String
        public let changes: String?
        public let redacted: Bool
    }
    public struct AnchorEvidence: Decodable, Equatable {
        public struct Channel: Decodable, Equatable {
            public let channel: String
            public let state: String
            public let artifactHash: String?
            public let snapshotHash: String
            enum CodingKeys: String, CodingKey {
                case channel, state, artifactHash = "artifact_sha256", snapshotHash = "snapshot_sha256"
            }
        }
        public let format: String
        public let throughOriginalID: String
        public let headHash: String
        public let complete: Bool
        public let channels: [Channel]
        enum CodingKeys: String, CodingKey {
            case format, complete, channels, throughOriginalID = "through_original_id", headHash = "head_hash"
        }
        func matches(_ proof: Verification) -> Bool {
            let isHash: (String) -> Bool = { $0.count == 64 && $0.allSatisfy { "0123456789abcdef".contains($0) } }
            guard format == "original-channel-anchor-evidence-v1", throughOriginalID == proof.throughOriginalID,
                  headHash == proof.headHash else { return false }
            if channels.isEmpty { return !complete && !proof.externallyAnchored }
            guard channels.count == 3, Set(channels.map(\.channel)) == Set(["OSS", "SMTP", "ADMIN_ARCHIVE"]),
                  Set(channels.map(\.snapshotHash)).count == 1, channels.allSatisfy({ isHash($0.snapshotHash) })
            else { return false }
            let expected = ["OSS": "STORED", "SMTP": "SMTP_ACCEPTED", "ADMIN_ARCHIVE": "ARCHIVED"]
            let waiting = Set(["PREPARED", "CONFIG_REQUIRED", "INFLIGHT", "UNKNOWN"])
            guard channels.allSatisfy({ row in
                if row.state == expected[row.channel] { return row.artifactHash.map(isHash) == true }
                return waiting.contains(row.state) && row.artifactHash == nil
            }) else { return false }
            let allRecorded = channels.allSatisfy { $0.state == expected[$0.channel] }
            return complete == allRecorded && proof.externallyAnchored == (proof.chainOK && complete)
        }
    }
    public struct Verification: Decodable, Equatable {
        public let chainOK: Bool
        public let linkedProjectionOK: Bool
        public let unprovenOriginalRows: Int64
        public let checkedRows: Int64
        public let throughOriginalID: String
        public let verifiedThroughOriginalID: String
        public let headHash: String
        public let frozen: Bool
        public let anchorEvidence: AnchorEvidence?
        public let externallyAnchored: Bool
        public let boundary: String
        enum CodingKeys: String, CodingKey {
            case chainOK = "chain_ok", linkedProjectionOK = "linked_projection_ok"
            case unprovenOriginalRows = "unproven_original_rows", checkedRows = "checked_rows"
            case throughOriginalID = "through_original_id", verifiedThroughOriginalID = "verified_through_original_id"
            case anchorEvidence = "anchor_evidence"
            case headHash = "head_hash", frozen, externallyAnchored = "externally_anchored", boundary
        }
    }
    private var storedVerification: Verification?
    public var verification: Verification? { isCurrent ? storedVerification : nil }
    public var canVerify: Bool { source == .governance && isCurrent && !busy }
    public enum State: Equatable { case idle, loading, ready, unavailable, closed }
    public private(set) var state: State = .idle
    public private(set) var hasMore = false
    private var storedRows: [Row] = []
    private var cursor: String?
    private var busy = false
    private var active = false
    private var generation = 0
    @ObservationIgnored private let captured: NativeChannelManagementIntegrationContext
    @ObservationIgnored private let channels: any NativeChannelManagementIntegrationContextProviding
    @ObservationIgnored private let context: RuntimeDependencyContext
    @ObservationIgnored private let transport: any HTTPTransport
    @ObservationIgnored private let current: () -> Bool
    @ObservationIgnored private let unauthorized: () -> Void
    public var isCurrent: Bool { active && current() && channels.contextIsCurrent(captured) }
    public var rows: [Row] { isCurrent ? storedRows : [] }
    public var canLoadMore: Bool { isCurrent && !busy && hasMore && cursor != nil }
    public init(captured: NativeChannelManagementIntegrationContext, channels: any NativeChannelManagementIntegrationContextProviding,
                context: RuntimeDependencyContext, transport: any HTTPTransport, current: @escaping () -> Bool,
                unauthorized: @escaping () -> Void, source: Source = .governance) throws {
        guard captured.ownerType == "CLUB", captured.serverPermissionNames.contains("VIEW_AUDIT"),
              captured.identity.owner.accountID == context.session.accountID,
              captured.identity.owner.namespace == context.session.namespace,
              captured.identity.owner.baseURL == context.baseURL.absoluteString,
              captured.identity.epoch == context.session.epoch, channels.contextIsCurrent(captured) else { throw APIError.unauthorized }
        self.source = source
        self.captured = captured; self.channels = channels; self.context = context; self.transport = transport
        self.current = current; self.unauthorized = unauthorized
    }
    public func deactivate() { active = false; generation += 1; storedOperations = []; storedRows = []; storedVerification = nil; cursor = nil; hasMore = false; state = .closed }
    public func activate() async { guard !active else { return }; active = true; await refresh() }
    public func refresh() async { await read(before: nil) }
    public func verifyOriginalChain() async { guard source == .governance else { return }; await read(before: nil, verify: true) }
    public func more() async { guard canLoadMore, let cursor else { return }; await read(before: cursor) }
    private func read(before: String?, verify: Bool = false) async {
        if source == .lifecycle { await readOperations(before: before); return }
        guard isCurrent, !busy else { return }
        busy = true; let run = generation; state = .loading; storedVerification = nil
        defer { busy = false }
        do {
            let fresh = try await channels.currentChannelContext(channelID: captured.channelID)
            guard isCurrent, run == generation, fresh == captured, fresh.serverPermissionNames.contains("VIEW_AUDIT") else { throw APIError.unauthorized }
            var query = [URLQueryItem(name: "guild_kind", value: "1"), URLQueryItem(name: "guild_id", value: captured.ownerID.rawValue),
                         URLQueryItem(name: "limit", value: "50"), URLQueryItem(name: "verify", value: verify ? "1" : "0")]
            if let before { query.append(URLQueryItem(name: "before", value: before)) }
            guard var parts = URLComponents(url: context.baseURL.appendingPathComponent("api/im/audit-log"), resolvingAgainstBaseURL: false) else { throw APIError.invalidRequest }
            parts.queryItems = query; guard let url = parts.url else { throw APIError.invalidRequest }
            var request = URLRequest(url: url); request.httpMethod = "GET"; request.httpShouldHandleCookies = false
            request.setValue(context.session.token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Accept")
            try Task.checkCancellation(); let (bytes, status) = try await transport.send(request)
            guard isCurrent, run == generation else { throw APIError.unauthorized }; try Task.checkCancellation()
            if status == 401 { unauthorized(); throw APIError.unauthorized }
            guard bytes.count <= 512 * 1024, let envelope = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw APIError.malformedResponse }
            let code = (envelope["code"] as? NSNumber)?.intValue
            if status == 401 || code == 401 { unauthorized(); throw APIError.unauthorized }
            guard (200..<300).contains(status), code == 200, let data = envelope["data"] as? [String: Any],
                  NativeChannelGovernanceNotice.positive(data["guild_kind"]) == "1",
                  NativeChannelGovernanceNotice.positive(data["guild_id"]) == captured.ownerID.rawValue,
                  let values = data["list"] as? [[String: Any]], values.count <= 50,
                  let more = data["has_more"] as? Bool else { throw APIError.malformedResponse }
            var checked: Verification?
            if verify {
                guard let proof = data["verify"] as? [String: Any] else { throw APIError.malformedResponse }
                let bytes = try JSONSerialization.data(withJSONObject: proof)
                let result = try JSONDecoder().decode(Verification.self, from: bytes)
                guard result.unprovenOriginalRows >= 0, result.checkedRows >= 0,
                      let through = Int64(result.throughOriginalID), through >= 0, String(through) == result.throughOriginalID,
                      let checkedThrough = Int64(result.verifiedThroughOriginalID), checkedThrough >= 0, checkedThrough <= through,
                      String(checkedThrough) == result.verifiedThroughOriginalID,
                      result.headHash.count == 64, result.headHash.allSatisfy({ "0123456789abcdef".contains($0) }),
                      ((result.boundary == "original-channel-audit-projection-v1; no historical backfill or external-anchor claim"
                        && result.anchorEvidence == nil && !result.externallyAnchored)
                       || (result.boundary == "original-channel-audit-projection-v1; no historical backfill; external evidence only when reported"
                        && result.anchorEvidence?.matches(result) == true)),
                      result.chainOK == (result.linkedProjectionOK && result.unprovenOriginalRows == 0),
                      !result.linkedProjectionOK || checkedThrough == through,
                      result.linkedProjectionOK || (result.frozen && values.isEmpty && !more)
                else { throw APIError.malformedResponse }
                checked = result
            }
            let page = try values.map(Self.row)
            var prior = before.flatMap(Int64.init)
            for row in page {
                guard let id = Int64(row.id), prior.map({ id < $0 }) ?? true else { throw APIError.malformedResponse }
                prior = id
            }
            let next = NativeChannelGovernanceNotice.positive(data["next_cursor"])
            guard more ? next != nil && next == page.last?.id : next == nil else { throw APIError.malformedResponse }
            if before == nil { storedRows = page }
            else {
                guard Set(storedRows.map(\.id)).isDisjoint(with: page.map(\.id)) else { throw APIError.malformedResponse }
                storedRows += page
            }
            cursor = next; hasMore = more; storedVerification = checked; state = .ready
        } catch {
            if run == generation { storedRows = []; storedVerification = nil; cursor = nil; hasMore = false; state = isCurrent ? .unavailable : .closed }
        }
    }
    private func readOperations(before: String?) async {
        guard isCurrent, !busy else { return }
        busy = true; let run = generation; state = .loading; storedVerification = nil
        defer { busy = false }
        do {
            let fresh = try await channels.currentChannelContext(channelID: captured.channelID)
            guard isCurrent, run == generation, fresh == captured, fresh.serverPermissionNames.contains("VIEW_AUDIT") else { throw APIError.unauthorized }
            let path = "api/channels/\(captured.channelID.rawValue)/op-log"
            guard var parts = URLComponents(url: context.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else { throw APIError.invalidRequest }
            var query = [URLQueryItem(name: "limit", value: "50")]
            if let before { query.append(URLQueryItem(name: "before_id", value: before)) }
            parts.queryItems = query; guard let url = parts.url else { throw APIError.invalidRequest }
            var request = URLRequest(url: url); request.httpMethod = "GET"; request.httpShouldHandleCookies = false
            request.setValue(context.session.token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Accept")
            try Task.checkCancellation(); let (bytes, status) = try await transport.send(request)
            guard isCurrent, run == generation else { throw APIError.unauthorized }; try Task.checkCancellation()
            if status == 401 { unauthorized(); throw APIError.unauthorized }
            guard bytes.count <= 512 * 1024, let envelope = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw APIError.malformedResponse }
            let code = (envelope["code"] as? NSNumber)?.intValue
            if status == 401 || code == 401 { unauthorized(); throw APIError.unauthorized }
            guard (200..<300).contains(status), code == 200, let data = envelope["data"] as? [String: Any],
                  let values = data["list"] as? [[String: Any]], values.count <= 50, let more = data["has_more"] as? Bool else { throw APIError.malformedResponse }
            let page = try values.map { try Self.operation($0, channelID: captured.channelID.rawValue) }
            var prior = before.flatMap(Int64.init)
            for row in page {
                guard let id = Int64(row.id), prior.map({ id < $0 }) ?? true else { throw APIError.malformedResponse }; prior = id
            }
            let next = NativeChannelGovernanceNotice.positive(data["next_cursor"])
            guard more ? next != nil && next == page.last?.id : next == nil else { throw APIError.malformedResponse }
            // Re-read the real source after receiving rows; a log record is never an authorization.
            let confirmed = try await channels.currentChannelContext(channelID: captured.channelID)
            guard isCurrent, run == generation, confirmed == captured, confirmed.serverPermissionNames.contains("VIEW_AUDIT") else { throw APIError.unauthorized }
            if before == nil { storedOperations = page }
            else {
                guard Set(storedOperations.map(\.id)).isDisjoint(with: page.map(\.id)) else { throw APIError.malformedResponse }
                storedOperations += page
            }
            cursor = next; hasMore = more; state = .ready
        } catch {
            if run == generation { storedOperations = []; storedVerification = nil; cursor = nil; hasMore = false; state = isCurrent ? .unavailable : .closed }
        }
    }
    private static func operation(_ value: [String: Any], channelID: String) throws -> OperationRow {
        guard let id = NativeChannelGovernanceNotice.positive(value["id"]),
              NativeChannelGovernanceNotice.positive(value["channel_id"]) == channelID,
              let action = value["action"] as? String, !action.isEmpty, action.count <= 64 else { throw APIError.malformedResponse }
        func state(_ key: String) throws -> Int? {
            guard let value = value[key], !(value is NSNull) else { return nil }
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue == Double(number.intValue), (0...4).contains(number.intValue) else { throw APIError.malformedResponse }
            return number.intValue
        }
        func optionalText(_ key: String, limit: Int) throws -> String? {
            guard let item = value[key], !(item is NSNull) else { return nil }
            guard let text = item as? String, text.count <= limit else { throw APIError.malformedResponse }; return text
        }
        let date: String
        if let text = value["create_time"] as? String, !text.isEmpty, text.count <= 100 { date = text }
        else if let number = value["create_time"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.int64Value >= 0,
                number.doubleValue == Double(number.int64Value) { date = number.stringValue } // Preserve raw source representation; do not guess epoch units.
        else { throw APIError.malformedResponse }
        let rawActor = value["operator_id"]
        let actor = NativeChannelGovernanceNotice.positive(rawActor)
        guard rawActor == nil || rawActor is NSNull || actor != nil else { throw APIError.malformedResponse }
        return OperationRow(id: id, channelID: channelID, action: action, fromStatus: try state("from_status"), toStatus: try state("to_status"),
                            operatorID: actor, requestID: try optionalText("request_id", limit: 128), reason: try optionalText("reason", limit: 1000), createdAt: date)
    }
    private static func row(_ value: [String: Any]) throws -> Row {
        guard let id = NativeChannelGovernanceNotice.positive(value["id"]),
              let channel = NativeChannelGovernanceNotice.positive(value["channel_id"]),
              let actor = value["actor_type"] as? String, !actor.isEmpty,
              let action = value["action"] as? String, !action.isEmpty,
              let target = value["target_type"] as? String, !target.isEmpty,
              let date = value["create_time"] as? String, !date.isEmpty,
              let available = value["changes_available"] as? Bool,
              let redacted = value["changes_redacted"] as? Bool else { throw APIError.malformedResponse }
        var changes: String?
        if available, let projected = value["changes_json"] as? [String: Any] {
            let bytes = try JSONSerialization.data(withJSONObject: projected, options: [.sortedKeys, .prettyPrinted])
            guard bytes.count <= 32 * 1024 else { throw APIError.malformedResponse }
            changes = String(data: bytes, encoding: .utf8)
        }
        return Row(id: id, channelID: channel, actorType: actor, actorID: NativeChannelGovernanceNotice.positive(value["actor_member_id"]),
                   action: action, targetType: target, targetID: NativeChannelGovernanceNotice.positive(value["target_id"]),
                   reason: value["reason"] as? String, createdAt: date, changes: changes, redacted: redacted)
    }
}
