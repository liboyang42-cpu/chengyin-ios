import Foundation

public struct PublishingLocalDraft: Codable, Equatable {
    public let version: Int
    public let ownerKey: String
    public let identity: UUID
    public let baseline: String
    public let quick: QuickPublishDraft?
    public let activity: ActivityPublishDraft?
    public init(session: PublishingSession, identity: UUID, baseline: String = "", quick: QuickPublishDraft? = nil, activity: ActivityPublishDraft? = nil) throws {
        guard (quick == nil) != (activity == nil) else { throw PublishModesError.invalidDraft }
        version = 1; ownerKey = session.storageKey; self.identity = identity; self.baseline = baseline; self.quick = quick; self.activity = activity
    }
}
/// Full drafts require the existing secure storage interface. No plaintext fallback.
@MainActor public final class PublishingDraftStore {
    private let storage: any ProjectEditDataStorage
    public init(storage: any ProjectEditDataStorage) { self.storage = storage }
    private func key(session: PublishingSession, id: UUID) -> String { "publishing.draft.v1." + Data((session.storageKey + ":" + id.uuidString).utf8).base64EncodedString() }
    public func save(_ draft: PublishingLocalDraft, session: PublishingSession) throws {
        guard draft.ownerKey == session.storageKey, draft.version == 1 else { throw PublishModesError.changedSession }
        let data = try JSONEncoder().encode(draft), key = key(session: session, id: draft.identity)
        try storage.write(data, key: key)
        guard try storage.read(key) == data else { throw PublishModesError.storage }
    }
    public func load(id: UUID, baseline: String = "", session: PublishingSession) throws -> PublishingLocalDraft? {
        guard let data = try storage.read(key(session: session, id: id)) else { return nil }
        let value = try JSONDecoder().decode(PublishingLocalDraft.self, from: data)
        guard value.version == 1, value.ownerKey == session.storageKey, value.identity == id,
              (value.quick == nil) != (value.activity == nil) else { throw PublishModesError.invalidContract }
        guard value.baseline == baseline else { throw PublishModesError.conflict }; return value
    }
    private func activeKey(session: PublishingSession, activity: Bool) -> String {
        "publishing.active.v1." + Data((session.storageKey + (activity ? ":activity" : ":quick")).utf8).base64EncodedString()
    }
    public func saveActive(_ draft: PublishingLocalDraft, session: PublishingSession) throws {
        try save(draft, session: session)
        let pointer = try JSONEncoder().encode(draft.identity), key = activeKey(session: session, activity: draft.activity != nil)
        try storage.write(pointer, key: key)
        guard try storage.read(key) == pointer else { throw PublishModesError.storage }
    }
    public func loadActive(activity: Bool, session: PublishingSession) throws -> PublishingLocalDraft? {
        guard let data = try storage.read(activeKey(session: session, activity: activity)) else { return nil }
        let id = try JSONDecoder().decode(UUID.self, from: data)
        guard let draft = try load(id: id, session: session), (draft.activity != nil) == activity else { throw PublishModesError.invalidContract }
        return draft
    }

    private func activityRequestKey(_ session: PublishingSession) -> String {
        "publishing.activity.request.v1." + Data(session.storageKey.utf8).base64EncodedString()
    }
    public func activityRequest(session: PublishingSession) throws -> ActivityCreateRequestContract.Saved? {
        guard let data = try storage.read(activityRequestKey(session)) else { return nil }
        let value = try JSONDecoder().decode(ActivityCreateRequestContract.Saved.self, from: data)
        guard value.ownerKey == session.storageKey, value.submit.valid,
              value.receipt == nil || value.receipt?.matches(value.submit) == true else { throw PublishModesError.invalidContract }
        return value
    }
    public func saveActivityRequest(_ value: ActivityCreateRequestContract.Saved, session: PublishingSession,
                                    expected: ActivityCreateRequestContract.Saved?) throws {
        guard value.ownerKey == session.storageKey, value.submit.valid,
              value.receipt == nil || value.receipt?.matches(value.submit) == true,
              try activityRequest(session: session) == expected,
              expected == nil || expected?.submit == value.submit || (expected?.submit.requestId != value.submit.requestId && expected?.receipt?.terminal == true),
              expected?.receipt?.terminal != true || expected?.submit != value.submit || (value.receipt?.terminal == true && value.receipt?.state == expected?.receipt?.state && value.receipt?.originalResult == expected?.receipt?.originalResult) else { throw PublishModesError.conflict }
        // The service verifies the account-wide replay lock is empty before replacement.
        // Keep prior request evidence, including a payload retained before a failed journal write.
        if let expected, expected.submit.requestId != value.submit.requestId {
            let previous = try JSONEncoder().encode(expected)
            let archive = activityRequestKey(session) + "." + expected.submit.requestId
            try storage.write(previous, key: archive)
            guard try storage.read(archive) == previous else { throw PublishModesError.storage }
        }
        let bytes = try JSONEncoder().encode(value), key = activityRequestKey(session)
        try storage.write(bytes, key: key)
        guard try storage.read(key) == bytes else { throw PublishModesError.storage }
    }

    private func stateRequestPrefix(_ session: PublishingSession) -> String { "publishing.state.requests.v1." + Data(session.storageKey.utf8).base64EncodedString() }
    public func stateRequest(id: String, session: PublishingSession) throws -> ProjectStateRequestContract.Saved? {
        guard UUID(uuidString: id)?.uuidString.lowercased() == id else { throw PublishModesError.invalidContract }
        guard let bytes = try storage.read(stateRequestPrefix(session) + "." + id) else { return nil }
        let value = try JSONDecoder().decode(ProjectStateRequestContract.Saved.self, from: bytes)
        guard value.ownerKey == session.storageKey, value.id == id, value.valid,
              value.receipt == nil || value.receipt?.matches(value.submit) == true else { throw PublishModesError.invalidContract }
        return value
    }
    public func stateRequests(session: PublishingSession) throws -> [ProjectStateRequestContract.Saved] {
        guard let bytes = try storage.read(stateRequestPrefix(session) + ".index") else { return [] }
        let ids = try JSONDecoder().decode([String].self, from: bytes)
        guard Set(ids).count == ids.count else { throw PublishModesError.invalidContract }
        return try ids.reversed().map {
            // A reserved index with no request is incomplete durable intent, not an empty history.
            guard let value = try stateRequest(id: $0, session: session) else { throw PublishModesError.storage }
            return value
        }
    }
    public func saveStateRequest(_ value: ProjectStateRequestContract.Saved, expected: ProjectStateRequestContract.Saved?, session: PublishingSession) throws {
        guard value.ownerKey == session.storageKey, value.valid,
              value.receipt == nil || value.receipt?.matches(value.submit) == true,
              try stateRequest(id: value.id, session: session) == expected,
              expected == nil || (expected?.submit == value.submit && expected?.resource == value.resource && expected?.action == value.action && expected?.title == value.title),
              expected?.receipt?.terminal != true || (value.receipt?.terminal == true && value.receipt?.state == expected?.receipt?.state && value.receipt?.originalResult == expected?.receipt?.originalResult) else { throw PublishModesError.conflict }
        let bytes = try JSONEncoder().encode(value), key = stateRequestPrefix(session) + "." + value.id
        let index = stateRequestPrefix(session) + ".index"
        var ids = try storage.read(index).map { try JSONDecoder().decode([String].self, from: $0) } ?? []
        if !ids.contains(value.id) { ids.append(value.id) }
        let indexBytes = try JSONEncoder().encode(ids); try storage.write(indexBytes, key: index)
        guard try storage.read(index) == indexBytes else { throw PublishModesError.storage }
        // Reserve the discoverable intent before its payload. A crash here fails closed on read.
        try storage.write(bytes, key: key); guard try storage.read(key) == bytes else { throw PublishModesError.storage }
    }

}
