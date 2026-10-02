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

}
