import Foundation
import CryptoKit
import Combine
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ClubWelcomeNoteFailure: Error { case disabled, forbidden, changed, tooLong, locked, notSent, rejected, revoked, unknown }
/// This capability is independent of profile images, public settings and member actions.
@MainActor public final class ClubWelcomeNoteDispatchAuthorization {
    private let request: URLRequest
    private let current: () -> Bool
    public private(set) var didForward = false
    init(request: URLRequest, current: @escaping () -> Bool) { self.request = request; self.current = current }
    public var isCurrent: Bool { !Task.isCancelled && current() }
    public func forward(_ request: URLRequest, start: () throws -> Void) throws {
        guard !didForward, self.request == request, isCurrent else { throw ClubWelcomeNoteFailure.notSent }
        didForward = true; try start()
    }
}
@MainActor public protocol ClubWelcomeNoteDispatching: AnyObject {
    var isConfigured: Bool { get }
    func send(_ request: URLRequest, authorization: ClubWelcomeNoteDispatchAuthorization) async throws -> (Data, Int)
}
@MainActor public struct ClubWelcomeNoteRuntime {
    public let transport: any ClubWelcomeNoteDispatching
    public let journal: any OperationPendingJournal
    public let approval: () -> OperationEndpointApproval?
    /// Optional v1 request history and independently approved read transport. No ordinary
    /// write/read approval is widened; nil retains the legacy unresolvable-request lock.
    public let originalJournal: ClubWelcomeNoteOriginalJournal?
    public let receiptTransport: (any ClubWelcomeNoteDispatching)?
    public let receiptApproval: () -> OperationEndpointApproval?
    public init(transport: any ClubWelcomeNoteDispatching, journal: any OperationPendingJournal,
                approval: @escaping () -> OperationEndpointApproval?,
                originalJournal: ClubWelcomeNoteOriginalJournal? = nil,
                receiptTransport: (any ClubWelcomeNoteDispatching)? = nil,
                receiptApproval: @escaping () -> OperationEndpointApproval? = { nil }) {
        self.transport = transport; self.journal = journal; self.approval = approval
        self.originalJournal = originalJournal; self.receiptTransport = receiptTransport; self.receiptApproval = receiptApproval
    }
}

/// Keeps the original POST /open-settings/welcome-note. Independently configured v1
/// headers bind that writer to its own immutable receipt. Old unbound requests remain UNKNOWN.
@MainActor public final class ClubWelcomeNoteService {
    public nonisolated static let path = "api/club/open-settings/welcome-note"
    private let configuration: APIConfiguration
    private let runtime: ClubWelcomeNoteRuntime
    private let currentSession: () -> ClubOperationsSession?
    private let revision: () -> UInt64
    public init(configuration: APIConfiguration, runtime: ClubWelcomeNoteRuntime,
                currentSession: @escaping () -> ClubOperationsSession?, revision: @escaping () -> UInt64) {
        self.configuration = configuration; self.runtime = runtime; self.currentSession = currentSession; self.revision = revision
    }
    public static func normalized(_ value: String) throws -> String {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // Java codePointCount / Mini code points, not Swift grapheme clusters or UTF-16.
        guard text.unicodeScalars.count <= 200 else { throw ClubWelcomeNoteFailure.tooLong }
        return text
    }
    public func available(identity: ClubReadIdentity) -> Bool {
        guard let session = currentSession(), session.identity == identity, let actor = identity.accountID,
              let approval = runtime.approval(), runtime.transport.isConfigured else { return false }
        return approval.paths == [Self.path] && approval.allows(configuration: configuration, namespace: session.storageNamespace, accountID: actor, path: Self.path)
            && (runtime.originalJournal == nil || canRecover(identity: identity))
    }
    private func owner(_ session: ClubOperationsSession) -> String { configuration.baseURL.absoluteString + "|" + session.ownerKey }
    private func key(_ clubID: Int) -> String { "club.welcome.note:\(clubID)" }
    public func pending(clubID: Int, identity: ClubReadIdentity) -> Bool {
        guard let session = currentSession(), session.identity == identity else { return true }
        do {
            if try runtime.journal.pending(ownerKey: owner(session), targetKey: key(clubID)) != nil { return true }
            return try runtime.originalJournal?.read(owner: owner(session), clubID: clubID).contains(where: { $0.state == "UNKNOWN" }) == true
        } catch { return true }
    }
    public func save(clubID: Int, note: String, previous: String?, identity: ClubReadIdentity,
                     access: any ClubOperationsAccess, ownerCurrent: @escaping () -> Bool) async throws -> String {
        let text = try Self.normalized(note)
        guard clubID > 0, available(identity: identity), ownerCurrent(), let captured = currentSession(),
              let approval = runtime.approval() else { throw ClubWelcomeNoteFailure.disabled }
        let generation = revision()
        let current = { [weak self, weak access] in
            guard let self, let access else { return false }
            return self.currentSession() == captured && self.revision() == generation && self.runtime.approval() == approval &&
                self.available(identity: identity) && access.identity == identity && ownerCurrent()
        }
        guard current() else { throw ClubWelcomeNoteFailure.notSent }
        let fresh = try await access.snapshot(target: .club(clubID))
        guard current(), !Task.isCancelled, fresh.target == .club(clubID), let profile = fresh.profile,
              profile.club.id == clubID, profile.club.isOwner else { throw ClubWelcomeNoteFailure.forbidden }
        guard profile.club.welcomeNote == previous else { throw ClubWelcomeNoteFailure.changed }
        guard !pending(clubID: clubID, identity: identity) else { throw ClubWelcomeNoteFailure.locked }
        if runtime.originalJournal != nil {
            return try await saveOriginal(clubID: clubID, text: text, session: captured, current: current)
        }
        let record = OperationPendingRecord(ownerKey: owner(captured), targetKey: key(clubID))
        guard try runtime.journal.pending(ownerKey: record.ownerKey, targetKey: record.targetKey) == nil else { throw ClubWelcomeNoteFailure.locked }
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(Self.path))
        request.httpMethod = "POST"; request.httpShouldHandleCookies = false; request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 30
        request.setValue(captured.token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["id": clubID, "welcomeNote": text], options: [.sortedKeys])
        let authorization = ClubWelcomeNoteDispatchAuthorization(request: request, current: current)
        try runtime.journal.write(record)
        do {
            let (data, status) = try await runtime.transport.send(request, authorization: authorization)
            guard authorization.didForward, authorization.isCurrent, data.count <= 65536 else { throw ClubWelcomeNoteFailure.unknown }
            let row = try? JSONDecoder().decode(Envelope.self, from: data)
            if status == 401 || status == 403 || row?.code == 401 || row?.code == 403 {
                // A forwarded request remains locked on revocation; not a no-send receipt.
                throw ClubWelcomeNoteFailure.revoked
            }
            // Original welcome-note returns the same generic business error for several
            // branches. A code500 alone cannot distinguish pre-write refusal from an
            // ambiguous persistence failure, so it must not release the replay lock.
            // Only the server's selectWelcomeNote readback confirms this operation.
            // Empty string is an acknowledged clear; absent/null is not a clear ACK.
            guard status == 200, row?.code == 200, let saved = row?.data?.welcomeNote,
                  saved.unicodeScalars.count <= 200 else { throw ClubWelcomeNoteFailure.unknown }
            var acknowledged = record; acknowledged.acknowledgedSteps = 1
            try runtime.journal.write(acknowledged); try runtime.journal.clear(acknowledged)
            return saved
        } catch {
            if !authorization.didForward { try? runtime.journal.clear(record); throw ClubWelcomeNoteFailure.notSent }
            if case ClubWelcomeNoteFailure.rejected = error { throw error }
            if case ClubWelcomeNoteFailure.revoked = error { throw error }
            throw ClubWelcomeNoteFailure.unknown
        }
    }
    private struct Envelope: Decodable {
        let code: Int; let data: Saved?
        enum CodingKeys: String, CodingKey { case code, data }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            code = try c.decode(Int.self, forKey: .code)
            // Business-rejection data may have another shape; its explicit non-200
            // code remains a rejection. A 200 with no exact Saved shape stays UNKNOWN.
            data = try? c.decode(Saved.self, forKey: .data)
        }
        struct Saved: Decodable { let welcomeNote: String? }
    }
}

@MainActor public final class ClubWelcomeNoteFlow: ObservableObject {
    public enum State: Equatable { case loading, ready, saving, saved(String), unavailable, notSent, rejected, revoked, unknown }
    @Published public var draft = ""
    @Published public private(set) var state: State = .loading
    @Published public private(set) var currentNote: String?
    @Published public private(set) var ownerConfirmed = false
    @Published public private(set) var originalResults: [ClubWelcomeNoteOriginalHistory] = []
    @Published public private(set) var recoveryUnavailable = false
    public let clubID: Int
    public let identity: ClubReadIdentity
    private let access: any ClubOperationsAccess
    private let service: ClubWelcomeNoteService?
    private var original: String?
    private var generation = UUID(), closed = false, busy = false
    public init(clubID: Int, identity: ClubReadIdentity, access: any ClubOperationsAccess) {
        self.clubID = clubID; self.identity = identity; self.access = access; service = access.welcomeNote
    }
    public var current: Bool { !closed && access.identity == identity }
    public var count: Int { draft.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count }
    public var canSave: Bool {
        guard current, !busy, ownerConfirmed, count <= 200, service?.available(identity: identity) == true else { return false }
        switch state { case .ready, .saved, .notSent, .rejected: return draft != (original ?? ""); default: return false }
    }
    public func load() async {
        guard current, !busy else { return }; busy = true; let stamp = generation
        state = .loading; ownerConfirmed = false; currentNote = nil; originalResults = []; recoveryUnavailable = false
        defer { if generation == stamp { busy = false } }
        // The author's immutable request is independent of today's club-owner status.
        // Recover before the mutable owner snapshot; never substitute current text.
        if let service, service.hasOriginalRequests(clubID: clubID, identity: identity) {
            do {
                originalResults = try await service.recoverOriginal(clubID: clubID, identity: identity,
                    viewCurrent: { [weak self] in self?.current == true && self?.generation == stamp })
            } catch {
                guard current, generation == stamp else { return }; recoveryUnavailable = true
            }
        }
        guard current, generation == stamp, !Task.isCancelled else { return }
        let unknown = service?.pending(clubID: clubID, identity: identity) == true
        do {
            let value = try await access.snapshot(target: .club(clubID))
            guard current, generation == stamp, !Task.isCancelled else { return }
            guard value.target == .club(clubID), let club = value.profile?.club, club.id == clubID, club.isOwner else { throw ClubWelcomeNoteFailure.forbidden }
            ownerConfirmed = true; currentNote = club.welcomeNote
            if unknown { state = .unknown } else { original = club.welcomeNote; draft = club.welcomeNote ?? ""; state = .ready }
        } catch {
            guard current, generation == stamp else { return }
            currentNote = nil; state = unknown ? .unknown : .unavailable
        }
    }
    public func save() async {
        guard canSave, let service else { return }; busy = true; state = .saving; let stamp = generation
        defer { if generation == stamp { busy = false } }
        do {
            let saved = try await service.save(clubID: clubID, note: draft, previous: original, identity: identity,
                access: access, ownerCurrent: { [weak self] in self?.current == true && self?.generation == stamp })
            guard current, generation == stamp, !Task.isCancelled else { return }
            original = saved; currentNote = saved; draft = saved; state = .saved(saved)
        } catch {
            guard current, generation == stamp else { return }
            switch error {
            case ClubWelcomeNoteFailure.notSent, ClubWelcomeNoteFailure.disabled, ClubWelcomeNoteFailure.tooLong, ClubWelcomeNoteFailure.changed, ClubWelcomeNoteFailure.forbidden: state = .notSent
            case ClubWelcomeNoteFailure.rejected: state = .rejected
            case ClubWelcomeNoteFailure.revoked: state = .revoked
            default: state = service.pending(clubID: clubID, identity: identity) ? .unknown : .notSent
            }
        }
    }
    public func close() { closed = true; generation = UUID(); draft = ""; original = nil; currentNote = nil; ownerConfirmed = false; originalResults = []; recoveryUnavailable = false }
}


/// Request metadata only. Draft text and credentials are never persisted. A settled
/// entry retains its exact audit ID/time; a later read cannot overwrite a terminal fact.
public struct ClubWelcomeNoteOriginalEntry: Codable, Equatable, Identifiable {
    public var id: String { requestID }
    public let schema: Int
    public let owner: String
    public let clubID: Int
    public let requestID: String
    public let sourceSHA256: String
    public fileprivate(set) var state: String
    public fileprivate(set) var auditID: Int?
    public fileprivate(set) var recordedAt: Int64?
    fileprivate init(owner: String, clubID: Int, text: String) {
        schema = 1; self.owner = owner; self.clubID = clubID
        requestID = UUID().uuidString.lowercased(); sourceSHA256 = Self.source(clubID: clubID, text: text)
        state = "UNKNOWN"
    }
    fileprivate var receiptFields: [String: Any] { ["clubId": clubID, "requestId": requestID, "sourceSHA256": sourceSHA256] }
    fileprivate static func digest(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined() }
    fileprivate static func source(clubID: Int, text: String) -> String { digest(["CLUB_WELCOME_NOTE_V1", String(clubID), digest(text)].joined(separator: "\u{001f}")) }
    fileprivate func validate(owner: String, clubID: Int) throws {
        guard schema == 1, self.owner == owner, !owner.isEmpty, self.clubID == clubID, clubID > 0,
              UUID(uuidString: requestID)?.uuidString.lowercased() == requestID,
              sourceSHA256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              ["UNKNOWN", "APPLIED", "REJECTED", "NOT_SENT"].contains(state) else { throw ClubWelcomeNoteFailure.locked }
        if state == "APPLIED" || state == "REJECTED" { guard (auditID ?? 0) > 0, (recordedAt ?? 0) > 0 else { throw ClubWelcomeNoteFailure.locked } }
        else { guard auditID == nil, recordedAt == nil else { throw ClubWelcomeNoteFailure.locked } }
    }
}

@MainActor public final class ClubWelcomeNoteOriginalJournal {
    private let directory: URL?
    public init(directory: URL?) { self.directory = directory }
    private func file(owner: String, clubID: Int) throws -> URL {
        guard let directory, !owner.isEmpty, clubID > 0 else { throw ClubWelcomeNoteFailure.locked }
        return directory.appendingPathComponent(ClubWelcomeNoteOriginalEntry.digest("\(owner.utf8.count):\(owner):\(clubID)") + ".json")
    }
    fileprivate func read(owner: String, clubID: Int) throws -> [ClubWelcomeNoteOriginalEntry] {
        let url = try file(owner: owner, clubID: clubID)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular, let size = attributes[.size] as? NSNumber,
              size.intValue > 0, size.intValue <= 1_048_576 else { throw ClubWelcomeNoteFailure.locked }
        let bytes = try Data(contentsOf: url)
        guard let text = String(data: bytes, encoding: .utf8), (try? ContentDraftJSON.parse(text)) != nil else { throw ClubWelcomeNoteFailure.locked }
        let values = try JSONDecoder().decode([ClubWelcomeNoteOriginalEntry].self, from: bytes)
        guard Set(values.map(\.requestID)).count == values.count, values.filter({ $0.state == "UNKNOWN" }).count <= 1 else { throw ClubWelcomeNoteFailure.locked }
        try values.forEach { try $0.validate(owner: owner, clubID: clubID) }; return values
    }
    fileprivate func reserve(_ entry: ClubWelcomeNoteOriginalEntry) throws {
        try entry.validate(owner: entry.owner, clubID: entry.clubID)
        var values = try read(owner: entry.owner, clubID: entry.clubID)
        guard entry.state == "UNKNOWN", !values.contains(where: { $0.state == "UNKNOWN" || $0.requestID == entry.requestID }) else { throw ClubWelcomeNoteFailure.locked }
        values.append(entry); try write(values, owner: entry.owner, clubID: entry.clubID)
    }
    fileprivate func settle(_ entry: ClubWelcomeNoteOriginalEntry, receipt: ClubWelcomeNoteOriginalReceipt?) throws {
        var values = try read(owner: entry.owner, clubID: entry.clubID)
        guard let i = values.firstIndex(where: { $0.requestID == entry.requestID }),
              values[i].sourceSHA256 == entry.sourceSHA256 else { throw ClubWelcomeNoteFailure.locked }
        var updated = entry
        if let receipt {
            guard ["APPLIED", "REJECTED"].contains(receipt.state), receipt.clubId == entry.clubID, receipt.requestId == entry.requestID,
                  receipt.sourceSHA256 == entry.sourceSHA256, let audit = receipt.auditId, audit > 0,
                  let time = receipt.recordedAt, time > 0 else { throw ClubWelcomeNoteFailure.unknown }
            updated.state = receipt.state; updated.auditID = audit; updated.recordedAt = time
        } else { updated.state = "NOT_SENT"; updated.auditID = nil; updated.recordedAt = nil }
        guard values[i].state == "UNKNOWN" || values[i] == updated else { throw ClubWelcomeNoteFailure.locked }
        values[i] = updated; try write(values, owner: entry.owner, clubID: entry.clubID)
    }
    private func write(_ values: [ClubWelcomeNoteOriginalEntry], owner: String, clubID: Int) throws {
        guard let directory else { throw ClubWelcomeNoteFailure.locked }
        try values.forEach { try $0.validate(owner: owner, clubID: clubID) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var root = directory; var options = URLResourceValues(); options.isExcludedFromBackup = true; try root.setResourceValues(options)
        let data = try JSONEncoder().encode(values), url = try file(owner: owner, clubID: clubID)
        guard data.count <= 1_048_576 else { throw ClubWelcomeNoteFailure.locked }
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        guard try read(owner: owner, clubID: clubID) == values else { throw ClubWelcomeNoteFailure.locked }
    }
}

public struct ClubWelcomeNoteOriginalReceipt: Decodable, Equatable {
    public let protocolVersion: Int, actorMemberId: Int, clubId: Int
    public let requestId: String, sourceSHA256: String, state: String
    public let welcomeNote: String?
    public let message: String?
    public let auditId: Int?
    public let recordedAt: Int64?
    fileprivate static func decode(_ data: Data, status: Int, entry: ClubWelcomeNoteOriginalEntry, actor: Int) throws -> Self {
        struct Envelope: Decodable { let code: Int; let data: ClubWelcomeNoteOriginalReceipt }
        guard status == 200, data.count <= 65536, let text = String(data: data, encoding: .utf8),
              (try? ContentDraftJSON.parse(text)) != nil,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ClubWelcomeNoteFailure.unknown }
        if let code = object["code"] as? Int, code == 401 || code == 403 { throw ClubWelcomeNoteFailure.revoked }
        guard let fields = object["data"] as? [String: Any], let state = fields["state"] as? String else { throw ClubWelcomeNoteFailure.unknown }
        let identity: Set<String> = ["protocolVersion", "actorMemberId", "clubId", "requestId", "sourceSHA256", "state"]
        let expected = state == "APPLIED" ? identity.union(["welcomeNote", "auditId", "recordedAt"])
            : state == "REJECTED" ? identity.union(["message", "auditId", "recordedAt"]) : identity
        guard Set(fields.keys) == expected else { throw ClubWelcomeNoteFailure.unknown }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data), value = envelope.data
        guard envelope.code == 200, value.protocolVersion == 1, value.actorMemberId == actor, value.clubId == entry.clubID,
              value.requestId == entry.requestID, value.sourceSHA256 == entry.sourceSHA256, ["APPLIED", "REJECTED", "UNKNOWN"].contains(value.state) else { throw ClubWelcomeNoteFailure.unknown }
        if value.state == "APPLIED" {
            guard let note = value.welcomeNote, note.unicodeScalars.count <= 200,
                  ClubWelcomeNoteOriginalEntry.source(clubID: entry.clubID, text: note) == entry.sourceSHA256,
                  (value.auditId ?? 0) > 0, (value.recordedAt ?? 0) > 0 else { throw ClubWelcomeNoteFailure.unknown }
        }
        if value.state == "REJECTED" {
            guard let message = value.message, !message.isEmpty, message.utf16.count <= 4096,
                  (value.auditId ?? 0) > 0, (value.recordedAt ?? 0) > 0 else { throw ClubWelcomeNoteFailure.unknown }
        }
        if entry.state == "APPLIED" || entry.state == "REJECTED" {
            guard value.state == entry.state, value.auditId == entry.auditID, value.recordedAt == entry.recordedAt else { throw ClubWelcomeNoteFailure.unknown }
        }
        return value
    }
}
public struct ClubWelcomeNoteOriginalHistory: Identifiable {
    public var id: String { entry.requestID }
    public let entry: ClubWelcomeNoteOriginalEntry
    public let receipt: ClubWelcomeNoteOriginalReceipt?
}

extension ClubWelcomeNoteService {
    public nonisolated static let receiptPath = "api/club/open-settings/welcome-note-receipt"
    public func canRecover(identity: ClubReadIdentity) -> Bool {
        guard let session = currentSession(), session.identity == identity, let actor = identity.accountID,
              runtime.originalJournal != nil, runtime.receiptTransport?.isConfigured == true,
              let grant = runtime.receiptApproval() else { return false }
        return grant.paths == [Self.receiptPath] && grant.allows(configuration: configuration, namespace: session.storageNamespace, accountID: actor, path: Self.receiptPath)
    }
    public func hasOriginalRequests(clubID: Int, identity: ClubReadIdentity) -> Bool {
        guard let session = currentSession(), session.identity == identity, clubID > 0, let journal = runtime.originalJournal else { return false }
        do { return try !journal.read(owner: owner(session), clubID: clubID).isEmpty } catch { return true }
    }
    /// A read-only recovery may survive loss of write approval or current club ownership.
    /// Account/deployment/epoch/read-approval/view lifetime still fence every response.
    public func recoverOriginal(clubID: Int, identity: ClubReadIdentity, viewCurrent: @escaping () -> Bool) async throws -> [ClubWelcomeNoteOriginalHistory] {
        guard canRecover(identity: identity), let captured = currentSession(), let actor = identity.accountID,
              let journal = runtime.originalJournal, let transport = runtime.receiptTransport,
              let grant = runtime.receiptApproval() else { throw ClubWelcomeNoteFailure.disabled }
        let generation = self.revision()
        let current = { [weak self] in
            guard let self else { return false }
            return self.currentSession() == captured && self.revision() == generation && self.runtime.receiptApproval() == grant
                && self.canRecover(identity: identity) && viewCurrent()
        }
        var results: [ClubWelcomeNoteOriginalHistory] = []
        let history = try journal.read(owner: owner(captured), clubID: clubID)
        for entry in history.filter({ $0.state == "UNKNOWN" }) + history.filter({ $0.state != "UNKNOWN" }) {
            guard current(), !Task.isCancelled else { throw ClubWelcomeNoteFailure.revoked }
            if entry.state == "NOT_SENT" { results.append(.init(entry: entry, receipt: nil)); continue }
            var request = originalRequest(path: Self.receiptPath, session: captured)
            request.httpBody = try JSONSerialization.data(withJSONObject: entry.receiptFields, options: .sortedKeys)
            let authorization = ClubWelcomeNoteDispatchAuthorization(request: request, current: current)
            let (data, status) = try await transport.send(request, authorization: authorization)
            guard authorization.didForward, authorization.isCurrent else { throw ClubWelcomeNoteFailure.unknown }
            if status == 401 || status == 403 { throw ClubWelcomeNoteFailure.revoked }
            let receipt = try ClubWelcomeNoteOriginalReceipt.decode(data, status: status, entry: entry, actor: actor)
            guard current(), !Task.isCancelled else { throw ClubWelcomeNoteFailure.revoked }
            if ["APPLIED", "REJECTED"].contains(receipt.state) { try journal.settle(entry, receipt: receipt) }
            results.append(.init(entry: entry, receipt: receipt))
        }
        guard current(), !Task.isCancelled else { throw ClubWelcomeNoteFailure.revoked }; return results
    }
    private func originalRequest(path: String, session: ClubOperationsSession) -> URLRequest {
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"; request.httpShouldHandleCookies = false; request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 30
        request.setValue(session.token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type"); return request
    }
    private func saveOriginal(clubID: Int, text: String, session: ClubOperationsSession, current: @escaping () -> Bool) async throws -> String {
        guard current(), canRecover(identity: session.identity), let actor = session.identity.accountID,
              let journal = runtime.originalJournal else { throw ClubWelcomeNoteFailure.disabled }
        let entry = ClubWelcomeNoteOriginalEntry(owner: owner(session), clubID: clubID, text: text)
        var request = originalRequest(path: Self.path, session: session)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["id": clubID, "welcomeNote": text], options: .sortedKeys)
        request.setValue(entry.requestID, forHTTPHeaderField: "X-Club-Welcome-Request-Id")
        request.setValue(entry.sourceSHA256, forHTTPHeaderField: "X-Club-Welcome-Source-SHA256")
        let authorization = ClubWelcomeNoteDispatchAuthorization(request: request, current: current)
        // Complete persistent request identity precedes dispatch. No stored draft is needed
        // because UNKNOWN has only a receipt route, never a silent writer retry.
        try journal.reserve(entry)
        do {
            guard current(), !Task.isCancelled else { throw ClubWelcomeNoteFailure.notSent }
            let (data, status) = try await runtime.transport.send(request, authorization: authorization)
            guard authorization.didForward, authorization.isCurrent else { throw ClubWelcomeNoteFailure.unknown }
            if status == 401 || status == 403 { throw ClubWelcomeNoteFailure.revoked }
            let receipt = try ClubWelcomeNoteOriginalReceipt.decode(data, status: status, entry: entry, actor: actor)
            guard ["APPLIED", "REJECTED"].contains(receipt.state), current(), !Task.isCancelled else { throw ClubWelcomeNoteFailure.unknown }
            try journal.settle(entry, receipt: receipt)
            if receipt.state == "REJECTED" { throw ClubWelcomeNoteFailure.rejected }
            guard let saved = receipt.welcomeNote else { throw ClubWelcomeNoteFailure.unknown }; return saved
        } catch {
            if !authorization.didForward { try? journal.settle(entry, receipt: nil); throw ClubWelcomeNoteFailure.notSent }
            if case ClubWelcomeNoteFailure.revoked = error { throw error }
            if case ClubWelcomeNoteFailure.rejected = error { throw error }
            throw ClubWelcomeNoteFailure.unknown
        }
    }
}
