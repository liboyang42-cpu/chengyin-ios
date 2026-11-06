import Foundation
import CoreFoundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A response adapter on the ORIGINAL transport, not another messaging client.
/// The injected underlying transport retains all endpoint grants/final-forward checks.
/// Converts only exact native decimal IDs/cursors for the unchanged original Int DTOs.
@MainActor @Observable public final class NativeChannelMessageOriginalWireBridge: HTTPTransport {
    private let binding: NativeChannelMessageBinding
    private let configuration: APIConfiguration
    private let underlying: any HTTPTransport
    private let current: () -> Bool
    private let received401: () -> Void
    private var generation = 0
    private var historySequence = 0
    private var fullHistory: NativeChannelMessageHistorySupplement?
    private var metadata: [NativeChannelMessageID: NativeChannelMessageSnapshot] = [:]
    public init(binding: NativeChannelMessageBinding, configuration: APIConfiguration,
                underlying: any HTTPTransport, current: @escaping () -> Bool, received401: @escaping () -> Void = {}) {
        self.binding = binding; self.configuration = configuration; self.underlying = underlying; self.current = current
        self.received401 = received401
    }
    public func retire() { generation += 1; fullHistory = nil; metadata = [:] }
    public func invalidate(_ id: NativeChannelMessageID) { metadata[id] = nil }
    public func snapshot(for original: MessagingMessage) -> NativeChannelMessageSnapshot? {
        guard current(), let id = NativeChannelMessageID(rawValue: String(original.id)),
              let row = metadata[id], row.message == original else { return nil }
        return row
    }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        guard current() else { throw APIError.notConfigured }
        let run = generation
        let mode = recognized(request)
        var sequence: Int?
        if case .history(_)? = mode { historySequence += 1; sequence = historySequence; fullHistory = nil }
        let (bytes, status) = try await underlying.send(request)
        if mode != nil, NativeChannelTextService.receivedUnauthorized(data: bytes, status: status) {
            received401()
            return (bytes, status) // Let the outer original Text transport also retire its captured approvals.
        }
        guard current(), generation == run, !Task.isCancelled else { throw CancellationError() }
        if let sequence, sequence != historySequence { throw CancellationError() }
        guard let mode else { return (bytes, status) } // Original unrelated routes are unchanged.
        guard bytes.count <= 2 * 1024 * 1024 else { throw APIError.malformedResponse }
        guard (200..<300).contains(status), var envelope = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              envelope["code"] as? Int == 200, var data = envelope["data"] as? [String: Any] else { return (bytes, status) }
        switch mode {
        case .history(let latest):
            guard let rows = data["list"] as? [[String: Any]] else { throw APIError.malformedResponse }
            let supplement = try JSONDecoder().decode(NativeChannelMessageHistorySupplement.self,
                from: JSONSerialization.data(withJSONObject: data))
            guard supplement.list.count <= 50, Set(supplement.list.map(\.id)).count == supplement.list.count,
                  supplement.list.allSatisfy({ $0.conversationID == binding.conversationID }) else { throw APIError.malformedResponse }
            data["list"] = try rows.map(normalizeMessage)
            for row in supplement.list where row.version >= (metadata[row.id]?.version ?? 0) { metadata[row.id] = row }
            for key in ["nextCursor", "nextAfter"] {
                if let value = data[key] as? String { data[key] = try exactInteger(value, zero: true) }
            }
            if latest { fullHistory = supplement }
        case .send:
            data = try normalizeMessage(data)
        case .sendReceipt:
            if let message = data["message"] as? [String: Any] {
                if let unavailable = Self.unavailableReceipt(message) {
                    data["message"] = unavailable
                } else {
                    data["message"] = try normalizeMessage(message)
                }
            }
        }
        envelope["data"] = data
        return (try JSONSerialization.data(withJSONObject: envelope), status)
    }
    /// Called only AFTER original NativeChannelHistoryModel.load replaced its cache.
    /// Exact equality prevents acknowledging another page/old response as that replacement.
    public func consumedFullReplacement(messages: [MessagingMessage]) throws -> NativeChannelMessageHistorySupplement {
        guard current(), let fullHistory, fullHistory.list.map(\.message) == messages else { throw APIError.malformedResponse }
        guard fullHistory.sync_contract == "VISIBLE_ORDER_PLUS_MUTATIONS_V1",
              fullHistory.legacy_cache_action == "RELOAD_ON_RESUME",
              NativeChannelMessageCursor.valid(fullHistory.mutation_cursor) else { throw APIError.malformedResponse }
        self.fullHistory = nil; return fullHistory
    }
    private enum Mode { case history(latest: Bool), send, sendReceipt }
    private func recognized(_ request: URLRequest) -> Mode? {
        guard let url = request.url, url.query == nil, url.fragment == nil,
              request.httpMethod == "POST", let fields = fields(request),
              fields["conversation_id"] == binding.conversationID.rawValue else { return nil }
        if url == configuration.baseURL.appendingPathComponent("api/im/messages") {
            return .history(latest: fields["cursor_id"] == "0" && fields["after_id"] == nil)
        }
        if url == configuration.baseURL.appendingPathComponent("api/im/send") { return .send }
        if url == configuration.baseURL.appendingPathComponent("api/im/send-receipt") { return .sendReceipt }
        return nil
    }
    private func fields(_ request: URLRequest) -> [String: String]? {
        let prefix = "multipart/form-data; boundary="
        guard let type = request.value(forHTTPHeaderField: "Content-Type"), type.hasPrefix(prefix),
              let data = request.httpBody, data.count <= 64 * 1024, let text = String(data: data, encoding: .utf8) else { return nil }
        let boundary = String(type.dropFirst(prefix.count)), end = "--\(boundary)--\r\n"
        guard !boundary.isEmpty, text.hasSuffix(end) else { return nil }
        let parts = String(text.dropLast(end.count)).components(separatedBy: "--\(boundary)\r\n")
        guard parts.first == "" else { return nil }
        var result: [String: String] = [:]
        for part in parts.dropFirst() {
            let header = "Content-Disposition: form-data; name=\""
            guard part.hasPrefix(header), part.hasSuffix("\r\n"), let separator = part.range(of: "\"\r\n\r\n") else { return nil }
            let start = part.index(part.startIndex, offsetBy: header.count)
            guard start < separator.lowerBound else { return nil }
            let key = String(part[start..<separator.lowerBound])
            guard result[key] == nil else { return nil }
            result[key] = String(part[separator.upperBound...].dropLast("\r\n".count))
        }
        return result
    }
    private func exactInteger(_ raw: String, zero: Bool) throws -> Int {
        guard NativeChannelMessageCursor.valid(raw), let value = Int(raw), zero || value > 0 else { throw APIError.malformedResponse }
        return value
    }
    private static func jsonBool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
    /// Whole JSON numbers only. Booleans are not 0 or 1. 1.5 does not become 1.
    private static func exactJSONInteger(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let whole = number.int64Value
        guard number.doubleValue == Double(whole), number.stringValue == String(whole), whole >= 0 else { return nil }
        return whole
    }
    /// Sparse or non-displayable receipt bodies keep the outer proof and mark themselves unavailable.
    static func unavailableReceipt(_ message: [String: Any]) -> [String: Any]? {
        let kind = Self.exactJSONInteger(message["msgType"])
        let unavailable = message["message_unavailable"]
        let unavailableIsBooleanFalse = unavailable == nil || Self.jsonBool(unavailable) == false
        let kindValue = kind.flatMap { Int(exactly: $0) }
        let displayable = Self.exactJSONInteger(message["status"]) == Int64(0) && kindValue != nil && kindValue != 0
            && NativeChannelMessageKind(rawValue: kindValue ?? -1) != nil
            && message["id"] is String && message["conversationId"] is String
            && unavailableIsBooleanFalse
        guard !displayable else { return nil }
        var sparse = message
        for key in ["content", "extraJson", "replyTo"] { sparse.removeValue(forKey: key) }
        sparse["message_unavailable"] = true
        return sparse
    }
    static func rewriteSendReceipt(_ data: [String: Any]) -> [String: Any] {
        var data = data
        if let message = data["message"] as? [String: Any], let unavailable = unavailableReceipt(message) {
            data["message"] = unavailable
        }
        return data
    }
    private func normalizeMessage(_ input: [String: Any]) throws -> [String: Any] {
        var row = input
        guard let conversation = row["conversationId"] as? String,
              conversation == binding.conversationID.rawValue, let id = row["id"] as? String else { throw APIError.malformedResponse }
        row["id"] = try exactInteger(id, zero: false); row["conversationId"] = try exactInteger(conversation, zero: false)
        if let sender = row["senderId"] as? String { row["senderId"] = try exactInteger(sender, zero: true) }
        if (row["status"] as? Int) != 0 || NativeChannelMessageKind(rawValue: row["msgType"] as? Int ?? -1) == nil || (row["msgType"] as? Int) == 0 {
            for key in ["content", "extraJson", "replyTo"] { row.removeValue(forKey: key) }
        }
        return row
    }
}

/// Same original history model, same underlying read. No new GET/POST or send queue.
@MainActor public final class NativeChannelMessageOriginalHistoryBinding {
    public let model: NativeChannelHistoryModel
    public let wire: NativeChannelMessageOriginalWireBridge
    public weak var coordinator: NativeChannelMessageCoordinator?
    private let invalidate: (NativeChannelMessageID) -> Void
    public init(model: NativeChannelHistoryModel, wire: NativeChannelMessageOriginalWireBridge,
                invalidate: @escaping (NativeChannelMessageID) -> Void) {
        self.model = model; self.wire = wire; self.invalidate = invalidate
    }
    public func refresh() async throws {
        // Original content is intentionally hidden until this replacement succeeds,
        // so activate the same existing model before its View's first onAppear.
        model.activate()
        guard model.isCurrent else { throw APIError.notConfigured }
        let joinedExistingRead = model.isLoading
        while model.isLoading {
            try await Task.sleep(nanoseconds: 50_000_000)
            try Task.checkCancellation()
            guard model.isCurrent else { throw CancellationError() }
        }
        if joinedExistingRead, model.loaded, model.issue == nil,
           let original = try? wire.consumedFullReplacement(messages: model.history.messages) {
            try acknowledge(original); return
        }
        await model.load()
        guard model.isCurrent, model.loaded, model.issue == nil else { throw APIError.malformedResponse }
        let original = try wire.consumedFullReplacement(messages: model.history.messages)
        try acknowledge(original)
    }
    private func acknowledge(_ original: NativeChannelMessageHistorySupplement) throws {
        guard let coordinator else { throw APIError.notConfigured }
        try coordinator.replacedHistory(cursor: original.mutation_cursor, contract: original.sync_contract,
                                        cacheAction: original.legacy_cache_action, rows: original.list)
    }
    public func invalidateOriginal(_ id: NativeChannelMessageID) { invalidate(id) }
}
