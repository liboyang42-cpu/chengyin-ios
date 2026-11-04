import Foundation
import Observation
import CryptoKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Canonical58 CommunityReportPolicy, not inferred from sender kind or current message text.
public enum NativeChannelReportReason: String, CaseIterable, Codable, Identifiable {
    case dangerous = "DANGEROUS", minorSafety = "MINOR_SAFETY", selfHarm = "SELF_HARM"
    case sexualContent = "SEXUAL_CONTENT", harassment = "HARASSMENT", hate = "HATE", fraud = "FRAUD"
    case impersonation = "IMPERSONATION", falseInformation = "FALSE_INFORMATION", spam = "SPAM"
    case privacy = "PRIVACY", intellectualProperty = "INTELLECTUAL_PROPERTY", other = "OTHER"
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .dangerous: "现实人身危险或违法行为"
        case .minorSafety: "未成年人安全"
        case .selfHarm: "自伤或自杀风险"
        case .sexualContent: "色情低俗内容"
        case .harassment: "人身攻击或骚扰"
        case .hate: "仇恨或歧视"
        case .fraud: "诈骗"
        case .impersonation: "冒充他人"
        case .falseInformation: "虚假信息"
        case .spam: "垃圾广告或站外导流"
        case .privacy: "隐私泄露"
        case .intellectualProperty: "知识产权或内容盗用"
        case .other: "其他"
        }
    }
}

@MainActor @Observable public final class NativeChannelReportFlow {
    public enum State: Equatable { case idle, reviewing, submitting, unknown, reading, acknowledged(reportID: String, status: String), unavailable }
    public private(set) var state: State = .idle
    public private(set) var messageID: Int?
    public private(set) var requestID: String?
    public private(set) var selectedReason: NativeChannelReportReason?
    public private(set) var note = ""
    public let scope: NativeChannelTextScope
    @ObservationIgnored private let context: RuntimeDependencyContext
    @ObservationIgnored private let transport: any HTTPTransport
    @ObservationIgnored private let storage: any ProjectEditDataStorage
    @ObservationIgnored private let current: () -> Bool
    @ObservationIgnored private let permitsWrite: () -> Bool
    @ObservationIgnored private let permitsRead: (String) -> Bool
    @ObservationIgnored private let unauthorized: () -> Void
    @ObservationIgnored private var pending: Record?
    @ObservationIgnored private var storageFailed = false
    @ObservationIgnored private let makeRequestID: () -> UUID
    private static var operations: [String: UUID] = [:]
    private struct Record: Codable, Equatable {
        let version: Int
        let scope: NativeChannelTextScope
        let messageID: Int
        let requestID: String
        let reason: NativeChannelReportReason
        let note: String?
        var fields: [String: String] {
            var values = ["target_type": "MESSAGE", "target_id": String(messageID), "reason_code": reason.rawValue, "submit_request_id": requestID]
            if let note { values["reason_text"] = note }; return values
        }
        var json: String { "{" + fields.keys.sorted().map { Self.quote($0) + ":" + Self.quote(fields[$0]!) }.joined(separator: ",") + "}" }
        var digest: String { SHA256.hash(data: Data(json.utf8)).map { String(format: "%02x", $0) }.joined() }
        private static func quote(_ value: String) -> String {
            var result = "\""
            for scalar in value.unicodeScalars {
                switch scalar.value {
                case 0x22: result += "\\\""
                case 0x5c: result += "\\\\"
                case 0x08: result += "\\b"
                case 0x0c: result += "\\f"
                case 0x0a: result += "\\n"
                case 0x0d: result += "\\r"
                case 0x09: result += "\\t"
                case 0..<0x20: result += String(format: "\\u%04x", scalar.value)
                default: result.unicodeScalars.append(scalar)
                }
            }
            return result + "\""
        }
    }
    private var key: String {
        let values = [scope.namespace, scope.baseURL, String(scope.accountID), String(scope.conversationID)]
        return "native-channel-report.v1." + Data(values.map { "\($0.utf8.count):\($0)" }.joined().utf8).base64EncodedString()
    }
    public init(context: RuntimeDependencyContext, conversationID: Int, transport: any HTTPTransport,
                storage: any ProjectEditDataStorage, current: @escaping () -> Bool,
                permitsWrite: @escaping () -> Bool, permitsRead: @escaping (String) -> Bool,
                unauthorized: @escaping () -> Void, makeRequestID: @escaping () -> UUID = { UUID() }) throws {
        self.context = context; scope = try NativeChannelTextScope(context: context, conversationID: conversationID)
        self.transport = transport; self.storage = storage; self.current = current
        self.permitsWrite = permitsWrite; self.permitsRead = permitsRead; self.unauthorized = unauthorized; self.makeRequestID = makeRequestID
        do {
            if let row = try readRecord() { adopt(row); state = .unknown }
        } catch { storageFailed = true; state = .unavailable }
    }
    public var isCurrent: Bool { current() }
    public var hasPending: Bool { pending != nil }
    public var canSubmit: Bool {
        isCurrent && !storageFailed && permitsWrite() && state != .submitting && state != .reading
            && (pending.map { permitsRead(receiptPath($0.requestID)) } ?? true)
    }
    public var canRecover: Bool {
        guard isCurrent, !storageFailed, let pending else { return false }
        return permitsRead(receiptPath(pending.requestID)) && state != .submitting && state != .reading
    }
    @discardableResult public func prepare(messageID: Int) -> Bool {
        guard canSubmit, messageID > 0 else { return false }
        if pending != nil { return self.messageID == messageID }
        self.messageID = messageID; requestID = nil; selectedReason = nil; note = ""; state = .reviewing; return true
    }
    public func select(reason: NativeChannelReportReason?, note: String) {
        guard state == .reviewing, pending == nil, isCurrent else { return }
        selectedReason = reason; self.note = note
    }
    public func submit() async {
        guard canSubmit else { return }
        let row: Record
        if let pending { row = pending }
        else {
            guard state == .reviewing, let messageID, let selectedReason, note.utf16.count <= 500 else { return }
            let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
            row = Record(version: 1, scope: scope, messageID: messageID, requestID: makeRequestID().uuidString,
                         reason: selectedReason, note: text.isEmpty ? nil : text)
        }
        guard let lease = begin() else { return }; defer { end(lease) }
        let fresh = pending == nil
        // The fresh UUID exists only here. A generic write grant or another
        // request's receipt cannot admit it to durable storage or the original POST.
        if fresh && !permitsRead(receiptPath(row.requestID)) { state = .unavailable; return }
        if pending != nil {
            // Explicit retry checks the original outcome under the same owner lease.
            // No missing/failed/PENDING lookup may authorize another write.
            state = .reading
            do {
                guard try readRecord() == row else { throw NativeChannelTextJournalError.pendingIntent }
                let data = try await request(path: receiptPath(row.requestID), body: nil)
                struct Lookup: Decodable {
                    struct Value: Decodable { let state: String; let retry_with_original_request: Bool? }
                    let data: Value
                }
                let observed = try JSONDecoder().decode(Lookup.self, from: data).data
                if observed.state == "APPLIED" { try resolve(data, row: row); return }
                guard observed.state == "NOT_FOUND", observed.retry_with_original_request == true,
                      isCurrent, !Task.isCancelled, permitsWrite(), try readRecord() == row else { state = .unknown; return }
            } catch { state = .unknown; return }
        }
        do { try save(row); adopt(row) } catch { storageFailed = true; state = .unavailable; return }
        state = .submitting
        do {
            let data = try await request(path: "api/im/report", body: Data(row.json.utf8), freshReceiptID: fresh ? row.requestID : nil)
            guard isCurrent else { state = .unknown; return }
            try resolve(data, row: row)
        } catch { state = .unknown }
    }
    public func recover() async {
        guard canRecover, let row = pending, let lease = begin() else { return }; defer { end(lease) }
        state = .reading
        do {
            let data = try await request(path: receiptPath(row.requestID), body: nil)
            guard isCurrent else { state = .unknown; return }; try resolve(data, row: row)
        } catch { state = .unknown }
    }
    private func receiptPath(_ request: String) -> String { "api/channel-platform/governance/reports/requests/" + request }
    private func request(path: String, body: Data?, freshReceiptID: String? = nil) async throws -> Data {
        guard isCurrent, (body == nil ? permitsRead(path) : permitsWrite()) else { throw APIError.notConfigured }
        guard freshReceiptID.map({ permitsRead(receiptPath($0)) }) ?? true else { throw APIError.notConfigured }
        var request = URLRequest(url: context.baseURL.appendingPathComponent(path))
        request.httpMethod = body == nil ? "GET" : "POST"; request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(context.session.token, forHTTPHeaderField: "Authorization")
        if let body { request.httpBody = body; request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        guard isCurrent else { throw APIError.unauthorized }; try Task.checkCancellation()
        struct Header: Decodable { let code: Int }
        guard data.count <= 64 * 1024 else { throw APIError.malformedResponse }
        let header = try? JSONDecoder().decode(Header.self, from: data)
        if status == 401 || header?.code == 401 { unauthorized(); throw APIError.unauthorized }
        guard (200..<300).contains(status), header?.code == 200 else { throw APIError.malformedResponse }
        return data
    }
    private func resolve(_ data: Data, row: Record) throws {
        struct Envelope: Decodable { let data: Receipt }
        struct Receipt: Decodable {
            let state: String
            let request_id: String?, reporter_member_id: String?, target_type: String?, target_id: String?
            let channel_id: String?, body_digest: String?, report_id: String?, audit_task_id: String?, status: String?
        }
        let value = try JSONDecoder().decode(Envelope.self, from: data).data
        // NOT_FOUND is not evidence that a concurrently committing original request never happened.
        guard value.state == "APPLIED", value.request_id == row.requestID,
              value.reporter_member_id == String(scope.accountID), value.target_type == "MESSAGE",
              value.target_id == String(row.messageID), value.channel_id == String(scope.conversationID),
              value.body_digest == row.digest, let report = value.report_id, let id = Int64(report), id > 0,
              let task = value.audit_task_id, let taskID = Int64(task), taskID > 0,
              let status = value.status, ["PENDING", "ACCEPTED", "REJECTED", "DUPLICATE"].contains(status) else { state = .unknown; return }
        guard try readRecord() == row else { throw NativeChannelTextJournalError.pendingIntent }
        try storage.remove(key); guard try readRecord() == nil else { throw NativeChannelTextJournalError.unavailable }
        pending = nil; state = .acknowledged(reportID: report, status: status)
    }
    private func adopt(_ row: Record) {
        pending = row; messageID = row.messageID; requestID = row.requestID; selectedReason = row.reason; note = row.note ?? ""
    }
    private func readRecord() throws -> Record? {
        guard let data = try storage.read(key) else { return nil }
        guard data.count <= 16 * 1024 else { throw NativeChannelTextJournalError.incompatible }
        let row = try JSONDecoder().decode(Record.self, from: data)
        let original = try JSONSerialization.jsonObject(with: data) as? NSDictionary
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as? NSDictionary
        guard row.version == 1, row.scope == scope, row.messageID > 0, UUID(uuidString: row.requestID) != nil,
              (row.note?.utf16.count ?? 0) <= 500, let original, let encoded, original == encoded else { throw NativeChannelTextJournalError.incompatible }
        return row
    }
    private func save(_ row: Record) throws {
        if let prior = try readRecord() { guard prior == row else { throw NativeChannelTextJournalError.pendingIntent }; return }
        try storage.write(JSONEncoder().encode(row), key: key)
        guard try readRecord() == row else { throw NativeChannelTextJournalError.unavailable }
    }
    private func begin() -> UUID? { guard Self.operations[key] == nil else { return nil }; let id = UUID(); Self.operations[key] = id; return id }
    private func end(_ id: UUID) { if Self.operations[key] == id { Self.operations[key] = nil } }
}
