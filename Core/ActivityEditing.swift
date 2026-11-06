import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Existing activity content has an independent approval; creation approval is not reused.
public struct ActivityEditingGrants: Equatable {
    /// Retain one value across selector evaluations; a replacement has a fresh revision.
    public let revision: UUID?
    public let read: OperationEndpointApproval?
    public let update: OperationEndpointApproval?
    public init(read: OperationEndpointApproval? = nil, update: OperationEndpointApproval? = nil) {
        revision = read == nil && update == nil ? nil : UUID()
        self.read = read; self.update = update
    }
}

public enum ActivityEditingField: String, CaseIterable, Codable {
    case name, description, imgUrl, imgArr, categoryIds, addressName, longitude, latitude, address, startDate, endDate, templateId
    public var timeOrPlace: Bool {
        [.addressName, .longitude, .latitude, .address, .startDate, .endDate].contains(self)
    }
}

public struct ActivityEditingSnapshot: Codable, Equatable {
    public let id: Int
    public let ownerID: Int
    public let timeLocationLocked: Bool
    public let raw: [String: ProjectEditJSON]
    public init(id: Int, value: ProjectEditJSON, session: PublishingSession) throws {
        guard id > 0, let body = value.object, body["id"]?.integer == id,
              let owner = body["memberId"]?.integer, owner == session.accountID,
              ["club", "merchant"].contains(session.role), body["gate"] == nil || body["gate"] == .bool(false),
              case .bool(let locked)? = body["timeLocationLocked"] else { throw PublishModesError.forbidden }
        if session.role == "merchant" {
            for key in ["clubId", "topicId"] {
                guard body[key] == nil || body[key] == .null || body[key]?.integer == 0 else { throw PublishModesError.forbidden }
            }
        }
        for field in ActivityEditingField.allCases {
            let value = body[field.rawValue]
            if field == .templateId {
                guard value == nil || value == .null || value?.integer.map({ $0 > 0 }) == true else { throw PublishModesError.invalidContract }
            } else {
                guard value == nil || value == .null || value?.text != nil else { throw PublishModesError.invalidContract }
            }
        }
        self.id = id; ownerID = owner; timeLocationLocked = locked; raw = body
    }
    /// A local content revision, not a server CAS token. Volatile browse counters are excluded.
    public var revision: Data? {
        var fields = raw.filter { ActivityEditingField(rawValue: $0.key) != nil }
        for key in ["id", "memberId", "timeLocationLocked", "clubId", "topicId", "status", "publishStatus", "omsTicketList"] {
            fields[key] = raw[key]
        }
        return ProjectEditPendingMaterials.exactData(fields)
    }
    public func text(_ field: ActivityEditingField) -> String {
        if field == .templateId { return raw[field.rawValue]?.integer.map(String.init) ?? "" }
        return raw[field.rawValue]?.text ?? ""
    }
}

public struct ActivityEditingDraft: Codable, Equatable, Identifiable {
    public let id: UUID
    public let source: ActivityEditingSnapshot
    public var inputs: [String: String]
    public init(source: ActivityEditingSnapshot) {
        id = UUID(); self.source = source
        inputs = Dictionary(uniqueKeysWithValues: ActivityEditingField.allCases.map { ($0.rawValue, source.text($0)) })
    }
    public func text(_ field: ActivityEditingField) -> String { inputs[field.rawValue] ?? source.text(field) }
    public mutating func set(_ field: ActivityEditingField, _ value: String) { inputs[field.rawValue] = value }
    public var changed: Bool { ActivityEditingField.allCases.contains { Array(text($0).utf8) != Array(source.text($0).utf8) } }
    public func body(session: PublishingSession) throws -> [String: ProjectEditJSON] {
        let validated = try ActivityEditingSnapshot(id: source.id, value: .object(source.raw), session: session)
        guard ProjectEditPendingMaterials.exactData(validated) == ProjectEditPendingMaterials.exactData(source) else { throw PublishModesError.invalidContract }
        guard changed, Set(inputs.keys) == Set(ActivityEditingField.allCases.map(\.rawValue)),
              !text(.name).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let start = ProjectEditValidation.dateTime(text(.startDate)),
              let end = ProjectEditValidation.dateTime(text(.endDate)), end > start else { throw PublishModesError.invalidDraft }
        var result: [String: ProjectEditJSON] = ["id": .number(Decimal(source.id))]
        for field in ActivityEditingField.allCases {
            let changed = Array(text(field).utf8) != Array(source.text(field).utf8)
            if source.timeLocationLocked && field.timeOrPlace && changed { throw PublishModesError.forbidden }
            if !changed { result[field.rawValue] = source.raw[field.rawValue]; continue }
            if field == .templateId {
                guard let id = Int(text(field)), id > 0 else { throw PublishModesError.invalidDraft }
                result[field.rawValue] = .number(Decimal(id))
            } else { result[field.rawValue] = .string(text(field)) }
        }
        // Changing either coordinate requires a complete finite pair; untouched source spelling survives.
        if text(.longitude) != source.text(.longitude) || text(.latitude) != source.text(.latitude) {
            guard let lng = Double(text(.longitude)), let lat = Double(text(.latitude)), lng.isFinite, lat.isFinite,
                  (-180...180).contains(lng), (-90...90).contains(lat) else { throw PublishModesError.invalidDraft }
        }
        if text(.categoryIds) != source.text(.categoryIds) {
            let parts = text(.categoryIds).split(separator: ",", omittingEmptySubsequences: false)
            let ids = parts.compactMap { Int($0) }
            guard !ids.isEmpty, ids.count == parts.count, ids.allSatisfy({ $0 > 0 }), Set(ids).count == ids.count else { throw PublishModesError.invalidDraft }
        }
        if text(.startDate) != source.text(.startDate) || text(.endDate) != source.text(.endDate) {
            guard let tickets = source.raw["omsTicketList"]?.array else { throw PublishModesError.invalidContract }
            for ticket in tickets {
                guard let value = ticket.object, let first = value["startTime"]?.text, let last = value["endTime"]?.text,
                      let ticketStart = ProjectEditValidation.dateTime(first), let ticketEnd = ProjectEditValidation.dateTime(last),
                      ticketEnd > ticketStart, ticketStart >= start, ticketEnd <= end else { throw PublishModesError.invalidDraft }
            }
        }
        if session.role == "merchant" { result["scope"] = .string("MERCHANT") }
        // Omitted tickets mean no ticket mutation. Never reconstruct a destructive ticket list from public summaries.
        return result
    }
}

public struct ActivityEditingReview: Equatable, Identifiable {
    public let id: UUID
    public let session: PublishingSession
    public let draft: ActivityEditingDraft
    public let body: [String: ProjectEditJSON]
    fileprivate init(session: PublishingSession, draft: ActivityEditingDraft, body: [String: ProjectEditJSON]) {
        id = UUID(); self.session = session; self.draft = draft; self.body = body
    }
}

public struct ActivityEditingSavedDraft: Codable, Equatable {
    public let version: Int
    public let ownerKey: String
    public let draft: ActivityEditingDraft
    public let requestID: UUID?
    public init(session: PublishingSession, draft: ActivityEditingDraft, requestID: UUID? = nil) {
        version = 1; ownerKey = session.storageKey; self.draft = draft; self.requestID = requestID
    }
}

@MainActor public final class ActivityEditingDraftStore {
    private let storage: any ProjectEditDataStorage
    fileprivate let journal: any OperationPendingJournal
    public init(storage: any ProjectEditDataStorage, journal: any OperationPendingJournal) {
        self.storage = storage; self.journal = journal
    }
    private func key(_ id: Int, _ session: PublishingSession) -> String {
        "activity.edit.v1." + Data((session.storageKey + ":" + String(id)).utf8).base64EncodedString()
    }
    public func save(_ value: ActivityEditingSavedDraft, session: PublishingSession) throws {
        guard value.ownerKey == session.storageKey, value.version == 1 else { throw PublishModesError.changedSession }
        let source = try ActivityEditingSnapshot(id: value.draft.source.id, value: .object(value.draft.source.raw), session: session)
        guard ProjectEditPendingMaterials.exactData(source) == ProjectEditPendingMaterials.exactData(value.draft.source),
              Set(value.draft.inputs.keys) == Set(ActivityEditingField.allCases.map(\.rawValue)) else { throw PublishModesError.invalidContract }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value), name = key(value.draft.source.id, session)
        if let pending = try journal.pending(ownerKey: session.storageKey, targetKey: ActivityEditingService.target(value.draft.source.id)) {
            // A second live editor cannot replace the original uncertain request's recovery material.
            guard value.requestID == pending.operationID, try storage.read(name) == data else { throw PublishModesError.uncertain }
            return
        }
        try storage.write(data, key: name)
        guard try storage.read(name) == data else { throw PublishModesError.storage }
    }
    public func load(id: Int, session: PublishingSession) throws -> ActivityEditingSavedDraft? {
        guard let data = try storage.read(key(id, session)) else { return nil }
        let value = try JSONDecoder().decode(ActivityEditingSavedDraft.self, from: data)
        guard value.version == 1, value.ownerKey == session.storageKey, value.draft.source.id == id else { throw PublishModesError.invalidContract }
        let source = try ActivityEditingSnapshot(id: id, value: .object(value.draft.source.raw), session: session)
        guard ProjectEditPendingMaterials.exactData(source) == ProjectEditPendingMaterials.exactData(value.draft.source),
              Set(value.draft.inputs.keys) == Set(ActivityEditingField.allCases.map(\.rawValue)) else { throw PublishModesError.invalidContract }
        return value
    }
}

/// Typed composition entry. Generic activity reads and creation routes remain separate.
@MainActor public protocol ActivityEditingHTTPTransport: HTTPTransport {
    func sendActivityEditing(_ request: URLRequest, activityID: Int, session: PublishingSession,
                             grants: ActivityEditingGrants) async throws -> (Data, Int)
}

public enum ActivityEditingWire {
    public static let readPath = "api/activity/info"
    public static let updatePath = "api/activity/update"
    public static func path(_ request: URLRequest, activityID: Int, configuration: APIConfiguration) -> String? {
        guard activityID > 0, request.httpMethod == "POST", request.httpBodyStream == nil,
              let url = request.url, let body = request.httpBody else { return nil }
        if url == configuration.baseURL.appendingPathComponent(Self.readPath) {
            let prefix = "multipart/form-data; boundary="
            guard let type = request.value(forHTTPHeaderField: "Content-Type"), type.hasPrefix(prefix),
                  let expected = try? AuthRequestBuilder.makeFormRequest(url: url, fields: ["id": String(activityID)],
                    token: nil, boundary: String(type.dropFirst(prefix.count))), expected.httpBody == body else { return nil }
            return Self.readPath
        }
        guard url == configuration.baseURL.appendingPathComponent(Self.updatePath),
              request.value(forHTTPHeaderField: "Content-Type") == "application/json",
              let fields = try? JSONDecoder().decode([String: ProjectEditJSON].self, from: body),
              fields["id"]?.integer == activityID,
              Set(fields.keys).isSubset(of: Set(ActivityEditingField.allCases.map(\.rawValue) + ["id", "scope"])),
              fields["scope"] == nil || fields["scope"] == .string("MERCHANT"),
              let name = fields["name"]?.text, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let startRaw = fields["startDate"]?.text, let endRaw = fields["endDate"]?.text,
              let start = ProjectEditValidation.dateTime(startRaw), let end = ProjectEditValidation.dateTime(endRaw), end > start else { return nil }
        for field in ActivityEditingField.allCases {
            if field == .templateId {
                guard fields[field.rawValue] == nil || fields[field.rawValue] == .null || fields[field.rawValue]?.integer.map({ $0 > 0 }) == true else { return nil }
            } else {
                guard fields[field.rawValue] == nil || fields[field.rawValue] == .null || fields[field.rawValue]?.text != nil else { return nil }
            }
        }
        return Self.updatePath
    }
}

@MainActor public final class ActivityEditingService {
    public static let readPath = ActivityEditingWire.readPath
    public static let updatePath = ActivityEditingWire.updatePath
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let grants: ActivityEditingGrants
    private var journal: any OperationPendingJournal { drafts.journal }
    public let drafts: ActivityEditingDraftStore
    private let credentials: () -> PublishingCredentials?
    private var reviews: [UUID: ActivityEditingReview] = [:]
    private var sending = false
    public init(configuration: APIConfiguration, transport: any HTTPTransport, grants: ActivityEditingGrants = .init(),
                drafts: ActivityEditingDraftStore,
                credentials: @escaping () -> PublishingCredentials?) {
        self.configuration = configuration; self.transport = transport; self.grants = grants
        self.drafts = drafts; self.credentials = credentials
    }
    public var currentSession: PublishingSession? { credentials()?.session }
    private func allowed(_ approval: OperationEndpointApproval?, _ path: String, _ session: PublishingSession) -> Bool {
        session.region == .china && approval?.allows(configuration: configuration, namespace: session.namespace,
            accountID: session.accountID, path: path) == true
    }
    public var canRead: Bool { currentSession.map { allowed(grants.read, Self.readPath, $0) } ?? false }
    public var canUpdate: Bool { currentSession.map { allowed(grants.update, Self.updatePath, $0) } ?? false }
    private func check(_ captured: PublishingCredentials, current: () -> Bool) throws {
        try Task.checkCancellation()
        guard current(), credentials() == captured else { throw PublishModesError.changedSession }
    }
    public static func target(_ id: Int) -> String { "activity.edit:\(id)" }
    public func pending(id: Int, session: PublishingSession) throws -> OperationPendingRecord? {
        guard currentSession == session else { throw PublishModesError.changedSession }
        return try journal.pending(ownerKey: session.storageKey, targetKey: Self.target(id))
    }
    public func load(id: Int, session: PublishingSession, current: @escaping () -> Bool = { true }) async throws -> ActivityEditingSnapshot {
        guard id > 0, let captured = credentials(), captured.session == session,
              allowed(grants.read, Self.readPath, session) else { throw PublishModesError.unavailable }
        try check(captured, current: current)
        let request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(Self.readPath),
            fields: ["id": String(id)], token: captured.token, includesBody: true)
        let (data, status) = try await dispatch(request, id: id, session: session)
        try check(captured, current: current)
        let envelope = try OperationAdapterHTTP.envelope(data)
        guard (200..<300).contains(status), envelope["code"]?.integer == 200, let value = envelope["data"] else {
            throw PublishModesError.rejected(envelope["msg"]?.text ?? "")
        }
        return try ActivityEditingSnapshot(id: id, value: value, session: session)
    }
    public func prepare(_ draft: ActivityEditingDraft, session: PublishingSession,
                        current: @escaping () -> Bool = { true }) async throws -> ActivityEditingReview {
        guard canUpdate, try pending(id: draft.source.id, session: session) == nil else { throw PublishModesError.uncertain }
        let body = try draft.body(session: session)
        let latest = try await load(id: draft.source.id, session: session, current: current)
        guard let revision = latest.revision, revision == draft.source.revision else { throw PublishModesError.conflict }
        let review = ActivityEditingReview(session: session, draft: draft, body: body)
        reviews[review.id] = review; return review
    }
    public func cancel(_ review: ActivityEditingReview) { reviews.removeValue(forKey: review.id) }
    public func invalidateReviews() { reviews.removeAll() }
    public func submit(_ review: ActivityEditingReview, current: @escaping () -> Bool = { true }) async -> PublishingWriteOutcome {
        guard !sending, reviews[review.id] == review, let captured = credentials(), captured.session == review.session,
              allowed(grants.update, Self.updatePath, review.session) else { return .notSent }
        sending = true; defer { sending = false }
        let record = OperationPendingRecord(operationID: review.id, ownerKey: review.session.storageKey, targetKey: Self.target(review.draft.source.id))
        let request: URLRequest
        do {
            try check(captured, current: current)
            guard try pending(id: review.draft.source.id, session: review.session) == nil else { return .unknown }
            let latest = try await load(id: review.draft.source.id, session: review.session, current: current)
            try check(captured, current: current)
            guard reviews[review.id] == review, latest.revision != nil, latest.revision == review.draft.source.revision,
                  try review.draft.body(session: review.session) == review.body else { return .notSent }
            // Another editor may have dispatched while this preflight read was suspended.
            guard try pending(id: review.draft.source.id, session: review.session) == nil else { return .unknown }
            request = try OperationAdapterHTTP.json(configuration: configuration, path: Self.updatePath,
                body: JSONEncoder().encode(review.body), token: captured.token)
            try drafts.save(.init(session: review.session, draft: review.draft, requestID: review.id), session: review.session)
            try journal.write(record)
            guard try pending(id: review.draft.source.id, session: review.session) == record else { return .unknown }
            reviews.removeValue(forKey: review.id)
        } catch { return .notSent }
        // No suspension between the persisted replay lock and dispatch. A cancelled/stale reply remains uncertain.
        do {
            let (data, status) = try await dispatch(request, id: review.draft.source.id, session: review.session)
            try check(captured, current: current)
            guard (200..<300).contains(status), let envelope = try? OperationAdapterHTTP.envelope(data),
                  let code = envelope["code"]?.integer else { return .unknown }
            guard code == 200 || [400, 401, 403, 404, 409, 422].contains(code) else { return .unknown }
            try journal.clear(record)
            return code == 200 ? .acknowledged : .rejected(envelope["msg"]?.text ?? "")
        } catch { return .unknown }
    }
    private func dispatch(_ request: URLRequest, id: Int, session: PublishingSession) async throws -> (Data, Int) {
        guard ActivityEditingWire.path(request, activityID: id, configuration: configuration) != nil else { throw PublishModesError.invalidContract }
        if let scoped = transport as? any ActivityEditingHTTPTransport {
            return try await scoped.sendActivityEditing(request, activityID: id, session: session, grants: grants)
        }
        return try await transport.send(request)
    }
    // load() is the sole recovery read. It never clears pending or interprets matching content as an ACK.
}
