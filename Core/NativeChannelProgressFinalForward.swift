import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Two independently supplied inputs. A channel context or a path never issues operations.
public struct NativeChannelProgressRuntimeSelection: Equatable {
    public let authority: NativeChannelProgressAuthoritySnapshot
    public let endpoints: OperationEndpointApproval
    public let endpointRevision: UUID
    public init(authority: NativeChannelProgressAuthoritySnapshot, endpoints: OperationEndpointApproval,
                endpointRevision: UUID) throws {
        guard authority.endpointApprovalRevision == endpointRevision,
              authority.identity.actorID == Int64(endpoints.accountID),
              authority.identity.namespace.utf8.elementsEqual(endpoints.namespace.utf8),
              authority.identity.origin.absoluteString.utf8.elementsEqual(endpoints.baseURL.absoluteString.utf8) else {
            throw NativeChannelProgressError.closed
        }
        self.authority = authority; self.endpoints = endpoints; self.endpointRevision = endpointRevision
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.authority == rhs.authority && lhs.endpointRevision == rhs.endpointRevision
            && lhs.endpoints.baseURL.absoluteString.utf8.elementsEqual(rhs.endpoints.baseURL.absoluteString.utf8)
            && lhs.endpoints.namespace.utf8.elementsEqual(rhs.endpoints.namespace.utf8)
            && lhs.endpoints.accountID == rhs.endpoints.accountID
            && Set(lhs.endpoints.paths.map { Data($0.utf8) }) == Set(rhs.endpoints.paths.map { Data($0.utf8) })
    }
}

/// The private host dispatcher must consume the composed fence at its actual send,
/// after any queue. A plain HTTPTransport cannot erase that requirement or be used as
/// a fallback. The original operation fence remains live through that final boundary.
@MainActor public final class NativeChannelProgressFinalForward: NativeChannelProgressDispatching {
    private let captured: RuntimeDependencyContext
    private let issued: NativeChannelProgressRuntimeSelection
    private let journal: NativeChannelProgressPrivacyJournal
    private let underlying: any NativeChannelProgressDispatching
    private let current: () -> RuntimeDependencyContext?
    private let selected: () -> NativeChannelProgressRuntimeSelection?
    private let presentation: () -> Bool
    private let receiptApproval: (NativeChannelProgressPrivacyCommand) -> OperationEndpointApproval?
    private var retired = false
    public init(context: RuntimeDependencyContext, selection: NativeChannelProgressRuntimeSelection,
                journal: NativeChannelProgressPrivacyJournal, underlying: any NativeChannelProgressDispatching,
                current: @escaping () -> RuntimeDependencyContext?,
                selected: @escaping () -> NativeChannelProgressRuntimeSelection?, presentation: @escaping () -> Bool,
                receiptApproval: @escaping (NativeChannelProgressPrivacyCommand) -> OperationEndpointApproval? = { _ in nil }) throws {
        let identity = selection.authority.identity
        guard identity.actorID == Int64(context.session.accountID), identity.sessionEpoch == String(context.session.epoch),
              identity.namespace.utf8.elementsEqual(context.session.namespace.utf8),
              identity.origin.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              journal.owner == NativeChannelProgressJournalOwner(identity) else { throw NativeChannelProgressError.closed }
        captured = context; issued = selection; self.journal = journal; self.underlying = underlying
        self.current = current; self.selected = selected; self.presentation = presentation; self.receiptApproval = receiptApproval
        guard isCurrent else { throw NativeChannelProgressError.closed }
    }
    public var isCurrent: Bool {
        guard !retired, presentation(), let runtime = current(), ContentDraftContextFence.matches(runtime, captured),
              runtime.session == captured.session, selected() == issued else { retired = true; return false }
        return true
    }
    public func send(_ request: URLRequest, fence: NativeChannelProgressDispatchFence) async throws -> (Data, Int) {
        try Task.checkCancellation()
        guard isCurrent, fence.isCurrent, let operation = try operation(for: request),
              issued.authority.operations.contains(operation) else { throw NativeChannelProgressError.closed }
        let original = (operation == .savePrivacy || operation == .receipt) ? try journal.restore() : nil
        let originalBody = try original?.wireBody()
        let receiptLease = operation == .receipt ? original.flatMap(receiptApproval) : nil
        if operation == .savePrivacy || operation == .receipt {
            guard original != nil else { throw NativeChannelProgressError.closed }
        }
        if operation == .receipt {
            guard let original, let receiptLease, approvesReceipt(receiptLease, command: original) else { throw NativeChannelProgressError.closed }
        }
        let finalFence = NativeChannelProgressDispatchFence { [weak self] in
            guard let self, self.isCurrent, fence.isCurrent else { return false }
            // Non-recovery reads deliberately never consult the durable write journal.
            if let original {
                guard let restored = try? self.journal.restore(), restored == original,
                      let originalBody, (try? restored.wireBody()) == originalBody else { return false }
            }
            if operation == .receipt {
                guard let original, let receiptLease, let latest = self.receiptApproval(original),
                      self.approvesReceipt(latest, command: original), Self.sameApproval(receiptLease, latest) else { return false }
            }
            return true
        }
        guard finalFence.isCurrent else { throw NativeChannelProgressError.closed }
        do {
            let result = try await underlying.send(request, fence: finalFence)
            guard finalFence.isCurrent else { throw NativeChannelProgressError.closed }
            return result
        } catch {
            guard finalFence.isCurrent else { throw NativeChannelProgressError.closed }; throw error
        }
    }
    private func approvesReceipt(_ lease: OperationEndpointApproval, command: NativeChannelProgressPrivacyCommand) -> Bool {
        lease.baseURL.absoluteString.utf8.elementsEqual(captured.baseURL.absoluteString.utf8)
            && lease.namespace.utf8.elementsEqual(captured.session.namespace.utf8) && lease.accountID == captured.session.accountID
            && lease.paths.contains("api/progress/requests/" + command.requestId)
    }
    private static func sameApproval(_ a: OperationEndpointApproval, _ b: OperationEndpointApproval) -> Bool {
        a.baseURL.absoluteString.utf8.elementsEqual(b.baseURL.absoluteString.utf8)
            && a.namespace.utf8.elementsEqual(b.namespace.utf8) && a.accountID == b.accountID
            && Set(a.paths.map { Data($0.utf8) }) == Set(b.paths.map { Data($0.utf8) })
    }
    private func receiptCommand(for url: URL) throws -> NativeChannelProgressPrivacyCommand? {
        let prefix = captured.baseURL.appendingPathComponent("api/progress/requests").absoluteString + "/"
        guard url.absoluteString.hasPrefix(prefix) else { return nil }
        guard let original = try journal.restore(),
              captured.baseURL.appendingPathComponent("api/progress/requests/" + original.requestId)
                .absoluteString.utf8.elementsEqual(url.absoluteString.utf8) else { return nil }
        return original
    }
    private func operation(for request: URLRequest) throws -> NativeChannelProgressOperation? {
        guard let url = request.url, url.user == nil, url.password == nil, url.fragment == nil,
              !request.httpShouldHandleCookies, request.httpBodyStream == nil,
              request.cachePolicy == .reloadIgnoringLocalCacheData,
              request.value(forHTTPHeaderField: "Authorization")?.utf8.elementsEqual(captured.session.token.utf8) == true,
              request.value(forHTTPHeaderField: "Accept") == "application/json",
              Set((request.allHTTPHeaderFields ?? [:]).keys.map { $0.lowercased() }).count == (request.allHTTPHeaderFields ?? [:]).count,
              Set((request.allHTTPHeaderFields ?? [:]).keys.map { $0.lowercased() }).isSubset(of: ["authorization", "accept", "content-type"]),
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = parts.queryItems ?? []
        guard Set(items.map(\.name)).count == items.count, items.allSatisfy({ $0.value != nil }) else { return nil }
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value!) })
        parts.query = nil
        guard let noQuery = parts.url else { return nil }
        // A newly generated original UUID is not an endpoint grant. The real host must
        // independently approve this exact persisted command's receipt path.
        if request.httpMethod == "GET", request.httpBody == nil,
           request.value(forHTTPHeaderField: "Content-Type") == nil, query.isEmpty,
           let original = try receiptCommand(for: noQuery), let lease = receiptApproval(original),
           approvesReceipt(lease, command: original) { return .receipt }
        guard let path = issued.endpoints.paths.first(where: {
                  !$0.contains("%") && !$0.contains("\\") && !$0.contains("//") && !$0.contains("#") && !$0.contains("?")
                      && !$0.split(separator: "/").contains(".") && !$0.contains("..")
                      && captured.baseURL.appendingPathComponent($0).absoluteString.utf8.elementsEqual(noQuery.absoluteString.utf8)
              }) else { return nil }
        func exact(_ required: Set<String>, optional: Set<String> = []) -> Bool {
            required.isSubset(of: Set(query.keys)) && Set(query.keys).isSubset(of: required.union(optional))
        }
        func integer(_ text: String?, positive: Bool) -> Int64? {
            guard let text, let value = Int64(text), String(value) == text, (positive ? value > 0 : value >= 0) else { return nil }; return value
        }
        func period() -> Bool { ["ALL", "TOPIC", "WEEK", "MONTH"].contains(query["period"] ?? "") }
        func page() -> Bool { guard let limit = integer(query["limit"], positive: true) else { return false }; return limit <= 50 && period() }
        if path == "api/privacy/progress", request.httpMethod == "POST" {
            guard query.isEmpty, request.value(forHTTPHeaderField: "Content-Type") == "application/json",
                  let original = try journal.restore(), request.httpBody == (try original.wireBody()) else { return nil }
            return .savePrivacy
        }
        guard request.httpMethod == "GET", request.httpBody == nil, request.value(forHTTPHeaderField: "Content-Type") == nil else { return nil }
        if path == "api/privacy/progress" {
            if let channel = issued.authority.channelID {
                return query == ["channel_id": String(channel)] ? .privacy : nil
            }
            return query.isEmpty ? .privacy : nil
        }
        guard let channel = issued.authority.channelID else { return nil }
        if path == "api/channel/\(channel)/board" { return query.isEmpty ? .definitions : nil }
        if path == "api/channel/\(channel)/progress/overview" { return query.isEmpty ? .overview : nil }
        if path == "api/progress/meter" {
            guard exact(["channel_id", "topic_id", "activity_id", "subject_type", "subject_id"]),
                  query["channel_id"] == String(channel), integer(query["topic_id"], positive: true) != nil,
                  integer(query["activity_id"], positive: false) != nil, query["subject_type"] == "MEMBER",
                  query["subject_id"] == String(issued.authority.identity.actorID) else { return nil }
            return .meter
        }
        let prefix = "api/channel/\(channel)/board/"
        guard path.hasPrefix(prefix) else { return nil }
        let tail = path.dropFirst(prefix.count).split(separator: "/").map(String.init)
        guard tail.count >= 2, tail[0].range(of: "^[a-z][a-z0-9_]{0,31}$", options: .regularExpression) != nil else { return nil }
        if tail.count == 2 {
            switch tail[1] {
            case "top": return exact(["period", "limit"], optional: ["cursor"]) && page() ? .top : nil
            case "detail":
                guard exact(["period", "limit"], optional: ["cursor", "filter[completed]", "filter[team_id]"]), page(),
                      query["filter[completed]"].map({ ["true", "false"].contains($0) }) ?? true,
                      query["filter[team_id]"].map({ integer($0, positive: true) != nil }) ?? true else { return nil }
                return .detail
            case "version": return query.isEmpty ? .version : nil
            default: return nil
            }
        }
        if tail.count == 3, tail[1] == "me" {
            if tail[2] == "best" { return exact(["period"]) && period() ? .best : nil }
            if tail[2] == "recent" { return exact(["period", "limit"], optional: ["cursor"]) && page() ? .recent : nil }
        }
        return nil
    }
}
