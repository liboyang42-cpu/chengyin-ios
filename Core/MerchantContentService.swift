import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Marker restricted by contract to transports that never access the network. Production
/// URLSessionTransport does not conform, even if a caller passes the test execution switch.
public protocol MerchantContentOfflineTransport: HTTPTransport {}

public struct MerchantContentSession: Equatable {
    public let accountID: Int, epoch: UInt64, storageScope: String
    fileprivate let token: String
    public init(accountID: Int, epoch: UInt64, storageScope: String, token: String) throws {
        guard accountID > 0, !storageScope.isEmpty, AuthRequestBuilder.isValidToken(token) else { throw MerchantContentFailure.invalid }
        self.accountID = accountID; self.epoch = epoch; self.storageScope = storageScope; self.token = token
    }
}
public struct MerchantContentPendingRecord: Codable, Equatable {
    public let storageScope: String, accountID: Int, merchantID: Int, target: String, action: String
    public let station: MerchantStationCommand?
    public var key: String { [storageScope, String(accountID), String(merchantID), target].map { "\($0.utf8.count):\($0)" }.joined() }
}
@MainActor public protocol MerchantContentPendingStorage: AnyObject {
    func records() throws -> [MerchantContentPendingRecord]
    func insert(_ record: MerchantContentPendingRecord) throws
    func remove(key: String) throws
}
@MainActor public final class MerchantContentMemoryPendingStorage: MerchantContentPendingStorage {
    private var values: [MerchantContentPendingRecord] = []
    public init() {}
    public func records() throws -> [MerchantContentPendingRecord] { values }
    public func insert(_ record: MerchantContentPendingRecord) throws { guard !values.contains(where: { $0.key == record.key }) else { throw MerchantContentFailure.locked }; values.append(record) }
    public func remove(key: String) throws { values.removeAll { $0.key == key } }
}
/// Private local recovery journal. Tokens, contact data and ordinary content drafts are never persisted.
/// Station command payload is preserved only to correlate its exact source-supported receipt.
@MainActor public final class MerchantContentFilePendingStorage: MerchantContentPendingStorage {
    private let url: URL
    public init(url: URL) { self.url = url }
    public func records() throws -> [MerchantContentPendingRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let rows = try JSONDecoder().decode([MerchantContentPendingRecord].self, from: Data(contentsOf: url))
            guard Set(rows.map(\.key)).count == rows.count, rows.allSatisfy({ $0.accountID > 0 && $0.merchantID > 0 && !$0.storageScope.isEmpty }) else { throw MerchantContentFailure.storage }
            return rows
        } catch { throw MerchantContentFailure.storage }
    }
    public func insert(_ record: MerchantContentPendingRecord) throws {
        var rows = try records(); guard !rows.contains(where: { $0.key == record.key }) else { throw MerchantContentFailure.locked }
        rows.append(record); try save(rows)
    }
    public func remove(key: String) throws { try save(records().filter { $0.key != key }) }
    private func save(_ rows: [MerchantContentPendingRecord]) throws {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(rows).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { throw MerchantContentFailure.storage }
    }
}
public struct MerchantContentReceipt: Equatable {
    public let message: String?
    public let data: MerchantContentValue
    public let station: MerchantStationReceipt?
}
@MainActor public protocol MerchantContentServing: AnyObject {
    var scope: UUID { get }
    var isConfigured: Bool { get }
    var isAuthenticated: Bool { get }
    var permitsWrites: Bool { get }
    func load(_ query: MerchantContentQuery) async throws -> MerchantContentSnapshot
    func perform(_ command: MerchantContentCommand, baseline: MerchantContentSnapshot) async throws -> MerchantContentReceipt
    func pending() throws -> [MerchantContentPendingRecord]
    func reconcileChapterInvitation(_ record: MerchantContentPendingRecord) async throws -> MerchantChapterInvitationReadback
    func chapterReplacementInvitationEffects(scope: ChapterReplacementInvitationScope, publisherProof: ChapterReplacementInvitationPublisherProof?) -> ChapterReplacementInvitationEffects?
    func chapterReplacementPublisherProof(topicID: Int, actorAccountID: Int, access: MerchantAccess?) async -> ChapterReplacementInvitationPublisherProof?
    func reconcile(_ record: MerchantContentPendingRecord) async throws -> MerchantContentReceipt
    func retryStation(_ record: MerchantContentPendingRecord) async throws -> MerchantContentReceipt
}
extension MerchantContentServing {
    /// Only the real service overrides this; other readers keep the intent lock untouched.
    public func reconcileChapterInvitation(_ record: MerchantContentPendingRecord) async throws -> MerchantChapterInvitationReadback {
        throw MerchantContentFailure.locked
    }
    public func chapterReplacementInvitationEffects(scope: ChapterReplacementInvitationScope, publisherProof: ChapterReplacementInvitationPublisherProof?) -> ChapterReplacementInvitationEffects? { nil }
    /// No topic-publisher read on this reader. Fail closed: a nil proof cannot invite.
    public func chapterReplacementPublisherProof(topicID: Int, actorAccountID: Int, access: MerchantAccess?) async -> ChapterReplacementInvitationPublisherProof? { nil }
}
/// Real-transport gate for chapter invite and accept/reject. Both default closed.
public struct MerchantContentWriteApproval: Equatable {
    public let chapterInvite: Bool
    public let chapterRespond: Bool
    public init(chapterInvite: Bool = false, chapterRespond: Bool = false) {
        self.chapterInvite = chapterInvite; self.chapterRespond = chapterRespond
    }
}
@MainActor public final class MerchantContentService: MerchantContentServing {
    /// This is a test-injection switch, never a production capability approval.
    public enum Execution: Equatable { case disabled, injectedOfflineHarness }
    private let configuration: APIConfiguration?
    private let transport: any HTTPTransport
    private let currentSession: () -> MerchantContentSession?
    private let onUnauthorized: (MerchantContentSession) -> Void
    private let journal: (any MerchantContentPendingStorage)?
    private let execution: Execution
    private let writeApproval: () -> MerchantContentWriteApproval
    private let requiredMerchantID: Int?
    private var previous: MerchantContentSession?
    private var stamp = UUID()
    public var scope: UUID { let s = currentSession(); if s != previous { previous = s; stamp = UUID() }; return stamp }
    public var isConfigured: Bool { configuration != nil }
    public var isAuthenticated: Bool { currentSession() != nil }
    public var permitsWrites: Bool { execution == .injectedOfflineHarness && transport is any MerchantContentOfflineTransport && journal != nil }
    /// Chapter invite / accept / reject on the real transport when this approval says so.
    /// Every other command stays on `permitsWrites`. The offline harness is not this path.
    public func permits(_ command: MerchantContentCommand) -> Bool {
        if execution == .injectedOfflineHarness { return permitsWrites }
        guard journal != nil, !(transport is any MerchantContentOfflineTransport) else { return false }
        switch command {
        case .invite: return writeApproval().chapterInvite
        case .respondChapterInvitation: return writeApproval().chapterRespond
        default: return false
        }
    }
    public init(configuration: APIConfiguration?, transport: any HTTPTransport, currentSession: @escaping () -> MerchantContentSession?, journal: (any MerchantContentPendingStorage)? = nil, execution: Execution = .disabled, requiredMerchantID: Int? = nil, onUnauthorized: @escaping (MerchantContentSession) -> Void = { _ in }, writeApproval: @escaping () -> MerchantContentWriteApproval = { .init() }) {
        self.configuration = configuration; self.transport = transport; self.currentSession = currentSession
        self.journal = journal; self.execution = execution; self.writeApproval = writeApproval
        self.requiredMerchantID = requiredMerchantID; self.onUnauthorized = onUnauthorized; previous = currentSession()
    }
    private enum Body { case none, json([String: MerchantContentValue]), form([String: String]) }
    private struct Envelope: Decodable { let code: Int; let msg: String?; let data: MerchantContentValue? }
    private func ensure(_ s: MerchantContentSession) throws {
        guard !Task.isCancelled, currentSession() == s else { throw MerchantContentFailure.changedSession }
    }
    private func envelope(_ path: String, _ body: Body = .none, query: [String: String] = [:], get: Bool = false, session: MerchantContentSession) async throws -> Envelope {
        try ensure(session); guard let configuration else { throw APIError.notConfigured }
        var components = URLComponents(url: configuration.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query.keys.sorted().map { URLQueryItem(name: $0, value: query[$0]) } }
        guard let url = components.url else { throw MerchantContentFailure.invalid }
        let form: [String: String]; if case .form(let fields) = body { form = fields } else { form = [:] }
        var request = try AuthRequestBuilder.makeFormRequest(url: url, fields: form, token: session.token, includesBody: { if case .form = body { return true }; return false }())
        if get { request.httpMethod = "GET" }
        if case .json(let fields) = body { request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONEncoder().encode(fields) }
        let (bytes, status) = try await transport.send(request)
        try ensure(session)
        if status == 401 { onUnauthorized(session); throw APIError.unauthorized }
        if status == 403 { throw MerchantContentFailure.denied }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        do { return try JSONDecoder().decode(Envelope.self, from: bytes) } catch { throw MerchantContentFailure.malformed }
    }
    private func accepted(_ e: Envelope, session: MerchantContentSession) throws -> MerchantContentValue {
        if e.code == 401 { onUnauthorized(session); throw APIError.unauthorized }
        if e.code == 403 { throw MerchantContentFailure.denied }
        guard e.code == 200 else { throw MerchantContentFailure.rejected(code: e.code, message: e.msg) }
        return e.data ?? .null
    }
    private func read(_ path: String, _ body: Body = .none, query: [String: String] = [:], get: Bool = false, session: MerchantContentSession) async throws -> MerchantContentValue {
        try accepted(await envelope(path, body, query: query, get: get, session: session), session: session)
    }
    private func access(_ session: MerchantContentSession, query: MerchantContentQuery) async throws -> MerchantAccess {
        let raw = try await read("api/merchant/access/me", session: session)
        let access = try raw.decoded(MerchantAccess.self)
        if query == .recruiting {
            let permissions = Set((raw["permissions"].array ?? []).compactMap { $0.text })
            guard permissions.contains("merchant:marketing:read") else { throw MerchantContentFailure.denied }
        }
        if query.requiresCoopOwner {
            guard MerchantChapterInvitation.accessAllows(access) else { throw MerchantContentFailure.denied }
        } else {
            guard access.active, access.merchantID != nil, !query.requiresProjects || access.allows(.projects) else { throw MerchantContentFailure.denied }
        }
        if let requiredMerchantID {
            guard requiredMerchantID > 0, access.merchantID == requiredMerchantID else { throw MerchantContentFailure.denied }
        }
        return access
    }
    public func load(_ query: MerchantContentQuery) async throws -> MerchantContentSnapshot {
        try query.validate(); guard let session = currentSession() else { throw APIError.unauthorized }
        let capturedScope = scope
        let access = try await access(session, query: query)
        let value = try await document(query, session: session)
        try ensure(session)
        return .init(query: query, scope: capturedScope, access: access, value: value, observedAt: Date(), ownerMemberID: session.accountID)
    }
    /// Cooperation-center plaza: same fresh `.recruiting` access gate, but keeps the whole
    /// marketing-home document so counts and truncation can be disclosed. Read-only.
    public func loadRecruitingHome() async throws -> MerchantContentSnapshot {
        guard let session = currentSession() else { throw APIError.unauthorized }
        let capturedScope = scope
        let access = try await access(session, query: .recruiting)
        let home = try await read("api/merchant/marketing-home", session: session)
        try ensure(session)
        return .init(query: .recruiting, scope: capturedScope, access: access, value: home, observedAt: Date())
    }
    /// A separate normal-entry reader calls this with a selected merchant and a scoped transport.
    public func loadOrdinaryMerchantParticipants(topicID: Int) async throws -> MerchantContentSnapshot {
        guard topicID > 0, let merchantID = requiredMerchantID, merchantID > 0 else { throw MerchantContentFailure.invalid }
        guard let session = currentSession() else { throw APIError.unauthorized }
        let capturedScope = scope
        let raw = try await read("api/merchant/access/me", session: session)
        let access = try raw.decoded(MerchantAccess.self)
        guard access.active, access.merchantID == merchantID, access.allows(.projects), let rawPermissions = raw["permissions"].array else {
            throw MerchantContentFailure.denied
        }
        let permissions = try rawPermissions.map { item -> String in
            guard case .string(let value) = item else { throw MerchantContentFailure.malformed }; return value
        }
        guard permissions.contains("merchant:verify:record:read") else { throw MerchantContentFailure.denied }
        let query = MerchantContentQuery.players(topicID: topicID)
        let value = try await document(query, session: session)
        try ensure(session)
        let clean = try MerchantOrdinaryParticipantsProjection.sanitized(value, mayReadContact: permissions.contains("merchant:crm:sensitive:read"))
        return .init(query: query, scope: capturedScope, access: access, value: clean, observedAt: Date())
    }
    private func document(_ q: MerchantContentQuery, session s: MerchantContentSession) async throws -> MerchantContentValue {
        func optionalTopic(_ id: Int?) -> [String: MerchantContentValue] { id.map { ["topicId": .integer($0)] } ?? [:] }
        let value: MerchantContentValue
        switch q {
        case .recruiting:
            let home = try await read("api/merchant/marketing-home", session: s)
            value = home["recruiting"]["items"]
        case .nodeAuthoring(let chapter):
            let applications = try await read("api/merchant/chapter-application/mine", session: s)
            guard let appRows = applications.array else { throw MerchantContentFailure.malformed }
            let templates = try await read("api/template/my-list", .form(["is_quote": "", "keyword": "", "category_id": "", "pageNum": "1", "pageSize": "100"]), session: s)
            guard let rows = templates.array ?? templates["rows"].array else { throw MerchantContentFailure.malformed }
            let nodes = try await read("api/merchant/chapter-node/mine", .form([:]), session: s)
            guard let nodeRows = nodes.array else { throw MerchantContentFailure.malformed }
            return .object(["applications": .array(appRows.filter { $0["chapterId"].integer == chapter }), "templates": .array(rows), "nodes": .array(nodeRows.filter { $0["chapterId"].integer == chapter })])
        case .projects: value = try await read("api/project/my", .form(["type": "all", "state": "all", "ownerType": "all", "scope": "MERCHANT", "pageNum": "1", "pageSize": "200"]), session: s)
        case .chapters(let id):
            let playerEnvelope = try await envelope("api/topic/info-to-user", .form(["id": String(id)]), session: s)
            if [401, 403].contains(playerEnvelope.code) { _ = try accepted(playerEnvelope, session: s) }
            var topic = playerEnvelope.data ?? .null
            // Source detail() deliberately tolerates the player's empty/unpublished projection, then
            // asks info-to-merchant. Do not turn that source fallback into a generic load failure.
            if (topic["name"].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                topic = try await read("api/topic/info-to-merchant", .form(["id": String(id)]), session: s)
            } else { _ = try accepted(playerEnvelope, session: s) }
            guard topic.object != nil else { throw MerchantContentFailure.malformed }
            if let returnedID = topic["id"].integer, returnedID != id { throw MerchantContentFailure.malformed }
            let e = try await envelope("api/topic/merchant-recruitment-chapters", .form(["id": String(id)]), session: s)
            if e.code != 200, let message = e.msg, let mode = MerchantRecruitMode.fromServer(message), e.code != 401, e.code != 403 {
                var result: [String: MerchantContentValue] = ["mode": .string(mode.rawValue), "topic": topic, "message": .string(message)]
                if mode == .registration {
                    do {
                        let check = try await envelope("api/registration/merchant/select", .form(["id": String(id)]), session: s)
                        if check.code == 200 { result["registered"] = .bool(false) }
                        else if check.code != 401 && check.code != 403 && (check.msg ?? "").contains("已报名") { result["registered"] = .bool(true) }
                        else { _ = try accepted(check, session: s); result["registered"] = .null }
                    } catch {
                        try ensure(s)
                        if error as? APIError == .unauthorized || error as? MerchantContentFailure == .denied { throw error }
                        result["registered"] = .null
                    }
                }
                return .object(result)
            }
            let chapters = try accepted(e, session: s); guard chapters.array != nil else { throw MerchantContentFailure.malformed }
            return .object(["mode": .string("chapters"), "topic": topic, "chapters": chapters])
        case .applications, .chapterInvitations: value = try await read("api/merchant/chapter-application/mine", session: s)
        case .chapterNodes(let id): value = try await read("api/merchant/chapter-node/mine", .form(id.map { ["topicId": String($0)] } ?? [:]), session: s)
        case .upcoming(let id): value = try await read("api/merchant/upcoming-runs", .json(["topicId": .integer(id)]), session: s)
        case .ownerApplications(let id): value = try await read("api/merchant/chapter-application/owner-list", .json(["topicId": .integer(id)]), session: s)
        case .invitable(let id): value = try await read("api/merchant/chapter-application/invitable", .json(ChapterReplacementInvitationInvitableRequest(topicID: id).fields()), session: s)
        case .pendingNodes(let id): value = try await read("api/merchant/chapter-node/pending", .form(["topicId": String(id)]), session: s)
        case .registrations(let filter): value = try await read("api/registration/merchant/list", .form(["status": String(filter)]), session: s)
        case .registration(let id):
            value = try await read("api/registration/merchant/info", query: ["id": String(id)], session: s)
            guard value["id"].integer == id else { throw MerchantContentFailure.malformed }
        case .project(let id):
            var fields = optionalTopic(id); fields["scope"] = .string("MERCHANT")
            value = try await read("api/project/home", .json(fields), session: s)
        case .players(let id):
            var fields = optionalTopic(id); fields["scope"] = .string("MERCHANT")
            value = try await read("api/project/players", .json(fields), session: s)
        case .city: value = try await read("api/merchant/city-node/list", session: s)
        case .claimable(let keyword):
            let catalog = try await read("api/merchant/city-node/list", session: s)
            let rows = try await read("api/merchant/city-node/claimable", .form(["keyword": keyword]), session: s)
            guard catalog.object != nil, rows.array != nil else { throw MerchantContentFailure.malformed }
            return .object(["rows": rows, "catalog": catalog])
        case .cityPlacement:
            let catalog = try await read("api/merchant/city-node/list", session: s)
            let profile = try await read("api/merchant/info", .form([:]), session: s)
            let templates = try await read("api/template/my-list", .form(["is_quote": "", "keyword": "", "category_id": "", "pageNum": "1", "pageSize": "100"]), session: s)
            let rows = templates.array ?? templates["rows"].array
            guard catalog.object != nil, profile.object != nil, let rows else { throw MerchantContentFailure.malformed }
            return .object(["catalog": catalog, "profile": profile, "templates": .array(rows)])
        case .npc(let id): value = try await read("api/merchant/chapter-node/npc/detail", .form(["nodeId": String(id)]), session: s)
        case .voice(let id): value = try await read("api/merchant/chapter-node/npc/voice/status", .form(["nodeId": String(id)]), session: s)
        case .poster(let id):
            let nodes = try await read("api/merchant/chapter-node/mine", .form([:]), session: s)
            guard let rows = nodes.array, rows.contains(where: { $0["id"].integer == id && $0["nodeAuditStatus"].integer == 1 }) else { throw MerchantContentFailure.denied }
            value = try await read("api/merchant/chapter-node/poster-code", .form(["nodeId": String(id)]), session: s)
        case .liveCode(let activity, let node):
            let raw = try await read("api/game/session/view", query: ["activityId": String(activity), "perspective": "MERCHANT"], get: true, session: s)
            let projection = try MerchantStationProjection(raw)
            guard projection.activityID == activity, projection.allowsLiveCode(nodeID: node) else { throw MerchantContentFailure.denied }
            value = try await read("api/merchant/chapter-node/live-checkin-code", .form(["nodeId": String(node)]), session: s)
            guard let ttl = value["ttlMs"].integer, ttl > 0, !(value["code"].text ?? "").isEmpty else { throw MerchantContentFailure.malformed }
        case .gameEntries: value = try await read("api/game/session/merchant/entries", get: true, session: s)
        case .game(let id):
            value = try await read("api/game/session/view", query: ["activityId": String(id), "perspective": "MERCHANT"], get: true, session: s)
            guard try MerchantStationProjection(value).activityID == id else { throw MerchantContentFailure.malformed }
        }
        switch q {
        case .recruiting, .applications, .chapterInvitations, .chapterNodes, .upcoming, .ownerApplications, .invitable, .pendingNodes, .claimable, .gameEntries:
            guard let rows = value.array, rows.allSatisfy({ $0.object != nil }) else { throw MerchantContentFailure.malformed }
            if q == .gameEntries {
                guard rows.allSatisfy({ ($0["activityId"].safeInteger ?? 0) > 0 && ($0["topicId"].safeInteger ?? 0) > 0 && ($0["stationCount"].safeInteger ?? 0) > 0 && !($0["activityName"].text ?? "").isEmpty }) else { throw MerchantContentFailure.malformed }
            }
        case .projects, .registrations, .players: guard value.object != nil, value["rows"].array != nil else { throw MerchantContentFailure.malformed }
        case .npc: guard value == .null || value.object != nil else { throw MerchantContentFailure.malformed }
        default: guard value.object != nil else { throw MerchantContentFailure.malformed }
        }
        return value
    }
    /// Read-only poster QR for an owned city node (`api/merchant/city-node/poster-code`). VERIFY is enforced server side.
    public func cityPosterCode(poiID: Int) async throws -> MerchantContentValue {
        guard poiID > 0 else { throw MerchantContentFailure.invalid }
        guard let session = currentSession() else { throw APIError.unauthorized }
        let value = try await read("api/merchant/city-node/poster-code", .form(["poiId": String(poiID)]), session: session)
        try ensure(session); return value
    }
    public func pending() throws -> [MerchantContentPendingRecord] {
        guard let session = currentSession() else { return [] }
        return try journal?.records().filter { $0.storageScope == session.storageScope && $0.accountID == session.accountID } ?? []
    }
    public func perform(_ command: MerchantContentCommand, baseline: MerchantContentSnapshot) async throws -> MerchantContentReceipt {
        guard permits(command), let journal else { throw MerchantContentFailure.disabled }
        guard let session = currentSession() else { throw APIError.unauthorized }
        let latest = try await load(baseline.query); try ensure(session)
        guard latest == baseline else { throw MerchantContentFailure.conflict }
        try command.validate(against: latest)
        guard let merchant = latest.access.merchantID else { throw MerchantContentFailure.denied }
        let station: MerchantStationCommand?; if case .station(let c) = command { station = c } else { station = nil }
        let record = MerchantContentPendingRecord(storageScope: session.storageScope, accountID: session.accountID, merchantID: merchant, target: command.scopeKey, action: command.key, station: station)
        // Persistence failure prevents dispatch. No content list or reload is allowed to remove uncertainty.
        try journal.insert(record); try ensure(session)
        let descriptor = try command.request()
        let body: Body; switch descriptor.body { case .json(let f): body = .json(f); case .form(let f): body = .form(f) }
        do {
            let e = try await envelope(descriptor.path, body, session: session)
            if e.code != 200 {
                // A source command's ordinary business rejection is definitive. HTTP/network ambiguity is not.
                if station == nil && ![401, 403].contains(e.code) { try journal.remove(key: record.key) }
                _ = try accepted(e, session: session)
            }
            var receipt = MerchantContentReceipt(message: e.msg, data: e.data ?? .null, station: nil)
            if let station { receipt = try await stationReceipt(station, session: session) }
            if case .place = command { guard MerchantCityPlacementReceipt.applicationID(receipt.data) != nil else { throw MerchantContentFailure.unknown } }
            if case .respondChapterInvitation = command {
                // An ACK is not the fact. Read the original application back before clearing the lock.
                try ensure(session)
                let verdict = try await reconcileChapterInvitation(record)
                switch verdict {
                case .confirmedCurrentFact(let reason, let row), .oppositeTerminal(let reason, let row):
                    return MerchantContentReceipt(message: reason ?? e.msg, data: row, station: nil)
                case .stillPending, .missing, .conflict:
                    throw MerchantContentFailure.unknown
                }
            }
            try ensure(session); try journal.remove(key: record.key)
            return receipt
        } catch {
            try ensure(session)
            if try journal.records().contains(where: { $0.key == record.key }) { throw MerchantContentFailure.unknown }
            throw error
        }
    }
    private func stationReceipt(_ command: MerchantStationCommand, session: MerchantContentSession) async throws -> MerchantContentReceipt {
        let data = try await read("api/game/session/receipt", query: ["activityId": String(command.activityID), "requestId": command.requestID], get: true, session: session)
        let receipt = try MerchantStationReceipt(data, command: command)
        return .init(message: receipt.reason, data: data, station: receipt)
    }
    /// Exact C7 readback after a lost respond response. Reads `mine` once, never resends the
    /// respond, and removes the intent lock only when the exact row is in a terminal state.
    /// Missing / conflicting / unreadable rows keep the lock (the thrown or returned verdict
    /// is surfaced by the caller without claiming this submission caused the server fact).
    public func reconcileChapterInvitation(_ record: MerchantContentPendingRecord) async throws -> MerchantChapterInvitationReadback {
        guard let session = currentSession(), record.storageScope == session.storageScope, record.accountID == session.accountID,
              let journal, try journal.records().contains(record), let intent = MerchantChapterInvitationIntent(record: record) else { throw MerchantContentFailure.locked }
        let access = try await access(session, query: .chapterInvitations)
        guard access.merchantID == record.merchantID, intent.merchantID == record.merchantID,
              intent.ownerMemberID == session.accountID else { throw MerchantContentFailure.denied }
        let value = try await read("api/merchant/chapter-application/mine", session: session)
        guard let rows = value.array ?? value["rows"].array else { throw MerchantContentFailure.malformed }
        let verdict = MerchantChapterInvitationReadback.evaluate(intent: intent, row: rows.first { $0["id"].integer == intent.applicationID }, currentOwnerMemberID: session.accountID)
        if verdict.clearsIntentLock { try ensure(session); try journal.remove(key: record.key) }
        return verdict
    }
    public func reconcile(_ record: MerchantContentPendingRecord) async throws -> MerchantContentReceipt {
        guard let session = currentSession(), record.storageScope == session.storageScope, record.accountID == session.accountID,
              let journal, try journal.records().contains(record), let command = record.station else { throw MerchantContentFailure.locked }
        let access = try await access(session, query: .game(activityID: command.activityID))
        guard access.merchantID == record.merchantID else { throw MerchantContentFailure.denied }
        let receipt = try await stationReceipt(command, session: session)
        try ensure(session); try journal.remove(key: record.key); return receipt
    }
    /// Explicit recovery only. Read the exact receipt first; replay never invents a requestId or payload.
    public func retryStation(_ record: MerchantContentPendingRecord) async throws -> MerchantContentReceipt {
        guard permitsWrites, let session = currentSession(), let journal,
              record.storageScope == session.storageScope, record.accountID == session.accountID,
              try journal.records().contains(record), let command = record.station else { throw MerchantContentFailure.locked }
        let access = try await access(session, query: .game(activityID: command.activityID))
        guard access.merchantID == record.merchantID else { throw MerchantContentFailure.denied }
        let raw = try await read("api/game/session/receipt", query: ["activityId": String(command.activityID), "requestId": command.requestID], get: true, session: session)
        if let terminal = try? MerchantStationReceipt(raw, command: command) {
            try ensure(session); try journal.remove(key: record.key)
            return .init(message: terminal.reason, data: raw, station: terminal)
        }
        // Only a correlated PENDING receipt permits exact replay. An unrelated/malformed response,
        // HTTP error or read timeout leaves the lock intact and never authorizes another send.
        guard raw["activityId"].safeInteger == command.activityID, raw["requestId"].text == command.requestID,
              raw["action"].text == command.action.rawValue, raw["outcome"].text == "PENDING",
              let revision = raw["revision"].safeInteger, revision >= 0 else { throw MerchantContentFailure.unknown }
        let latest = try await load(.game(activityID: command.activityID)); try ensure(session)
        guard latest.access.merchantID == record.merchantID else { throw MerchantContentFailure.denied }
        try command.validate(projection: MerchantStationProjection(latest.value))
        _ = try accepted(await envelope("api/game/session/command", .json(command.fields()), session: session), session: session)
        let receipt = try await stationReceipt(command, session: session)
        try ensure(session); try journal.remove(key: record.key); return receipt
    }

}

extension MerchantContentService {
    /// C9 adapter over this service's real endpoints. `sendInvite` requires the
    /// caller-supplied publisher proof to verify this plan's topic and actor. This
    /// method does not fetch or invent that proof. It re-loads the `.invitable`
    /// baseline, then performs the invite exactly once through the existing
    /// journal/`perform` path. `permits` is the chapter-invite gate. Nothing here retries.
    public func chapterReplacementInvitationEffects(scope: ChapterReplacementInvitationScope, publisherProof: ChapterReplacementInvitationPublisherProof?) -> ChapterReplacementInvitationEffects? {
        return ChapterReplacementInvitationEffects(
            loadVacancyRows: { [weak self] topic in
                guard let self else { throw ChapterReplacementInvitationFailure.unknown }
                return try await self.load(.ownerApplications(topicID: topic)).rows
            },
            loadCandidateRows: { [weak self] request in
                guard let self else { throw ChapterReplacementInvitationFailure.unknown }
                return try await self.chapterReplacementRows(path: ChapterReplacementInvitationInvitableRequest.path, fields: request.fields(), gate: .invitable(topicID: request.topicID))
            },
            loadExistingRows: { [weak self] topic, _ in
                guard let self else { throw ChapterReplacementInvitationFailure.unknown }
                return try await self.load(.ownerApplications(topicID: topic)).rows
            },
            sendInvite: { [weak self] plan in
                guard let self else { throw ChapterReplacementInvitationFailure.unknown }
                guard let publisherProof, publisherProof.verified,
                      publisherProof.topicID == plan.topicID,
                      publisherProof.actorAccountID == plan.actorAccountID else {
                    throw ChapterReplacementInvitationFailure.notTopicPublisher
                }
                // Closed execution never reaches the invite POST. This is a definitive
                // local refusal, not an unknown outcome, so the intent lock is released.
                guard self.permits(.invite(chapterID: plan.candidate.chapterID, merchantMemberID: plan.candidate.merchantMemberID,
                                           replacementOfOfferID: plan.candidate.replacementOfOfferID, scope: plan.scope.wireValue, message: plan.message)) else {
                    throw ChapterReplacementInvitationFailure.denied
                }
                let baseline = try await self.load(.invitable(topicID: plan.topicID))
                do {
                    _ = try await self.perform(.invite(chapterID: plan.candidate.chapterID, merchantMemberID: plan.candidate.merchantMemberID,
                                                       replacementOfOfferID: plan.candidate.replacementOfOfferID, scope: plan.scope.wireValue, message: plan.message),
                                               baseline: baseline)
                } catch MerchantContentFailure.unknown {
                    throw ChapterReplacementInvitationFailure.unknown
                } catch MerchantContentFailure.disabled {
                    throw ChapterReplacementInvitationFailure.denied
                } catch MerchantContentFailure.rejected {
                    throw ChapterReplacementInvitationFailure.denied
                } catch MerchantContentFailure.denied {
                    throw ChapterReplacementInvitationFailure.denied
                }
            },
            loadOwnerListRows: { [weak self] request in
                guard let self else { throw ChapterReplacementInvitationFailure.unknown }
                return try await self.chapterReplacementRows(path: ChapterReplacementInvitationOwnerListRequest.path, fields: request.fields(), gate: .ownerApplications(topicID: request.topicID))
            },
            loadOwnerMineRows: { [weak self] request in
                guard let self else { throw ChapterReplacementInvitationFailure.unknown }
                return try await self.chapterReplacementRows(path: ChapterReplacementInvitationOwnerMineRequest.path, fields: request.fields(), gate: .projects)
            })
    }
    /// Fresh `api/topic/info-to-user` for this signed-in member only.
    /// The merchant-visible topic document is not a publisher proof, and
    /// access/me's owner member id is not substituted for the actor.
    public func chapterReplacementPublisherProof(topicID: Int, actorAccountID: Int, access: MerchantAccess?) async -> ChapterReplacementInvitationPublisherProof? {
        guard topicID > 0, actorAccountID > 0, let session = currentSession(), session.accountID == actorAccountID else { return nil }
        let mapped = access?.active == true && access?.isOwner == true && access?.allows(.projects) == true
        do {
            let value = try await read("api/topic/info-to-user", .form(["id": String(topicID)]), session: session)
            try ensure(session)
            return ChapterReplacementInvitationPublisherProof.fromFreshTopicRead(
                topicID: topicID, actorAccountID: actorAccountID, document: value, projectManageOwnerMapped: mapped)
        } catch { return nil }
    }
    fileprivate func chapterReplacementRows(path: String, fields: [String: MerchantContentValue], gate: MerchantContentQuery) async throws -> [MerchantContentValue] {
        guard let session = currentSession() else { throw APIError.unauthorized }
        _ = try await access(session, query: gate)
        let value = try await read(path, .json(fields), session: session)
        guard let rows = value.array ?? value["rows"].array else { throw MerchantContentFailure.malformed }
        try ensure(session); return rows
    }
}

