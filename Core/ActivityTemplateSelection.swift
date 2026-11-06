import Foundation

/// A choice from the existing quotable-template read. No publication or write capability.
public struct ActivityTemplateChoice: Equatable, Identifiable {
    public enum Availability: String { case available, albumOnly, unsupported }
    public let id: AuthoringPlayTemplateID
    public let title: String
    public let availability: Availability
    public let raw: [String: ProjectEditJSON]
    public init(_ value: ProjectEditJSON) throws {
        guard let fields = value.object, let number = fields["id"]?.integer,
              let id = AuthoringPlayTemplateID(rawValue: number), let title = fields["title"]?.text ?? fields["name"]?.text,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PublishModesError.invalidContract }
        self.id = id; self.title = title; raw = fields
        availability = Self.availability(fields["advancedConfigJson"])
    }
    private static func availability(_ value: ProjectEditJSON?) -> Availability {
        let fields: [String: ProjectEditJSON]
        switch value {
        case nil, .null?, .string("")?: return .available
        case .object(let object)?: fields = object
        case .string(let text)?:
            // Reuse the existing bounded grammar/duplicate-key validator for nested JSON.
            guard let decoded = try? ApprovedTopicReleaseWire.envelope(Data(text.utf8)) else { return .unsupported }
            fields = decoded
        default: return .unsupported
        }
        guard let album = fields["album"], album != .null else { return .available }
        guard let album = album.object else { return .unsupported }
        switch album["enabled"] {
        case .bool(true)?: return .albumOnly
        case nil, .null?, .bool(false)?: return .available
        default: return .unsupported
        }
    }
    public static func page(_ value: ProjectEditJSON) throws -> [Self] {
        guard let rows = value.object?["rows"]?.array else { throw PublishModesError.invalidContract }
        let choices = try rows.map(Self.init)
        guard Set(choices.map(\.id)).count == choices.count else { throw PublishModesError.invalidContract }
        return choices
    }
}

/// Only the chosen template reference may change; the complete input draft is the owner fence.
public struct ActivityTemplateSelectionTarget: Equatable {
    public let session: PublishingSession
    public let draftID: UUID
    private let source: Data
    public init(session: PublishingSession, draftID: UUID, draft: ActivityPublishDraft) throws {
        guard session.accountID > 0, let bytes = ProjectEditPendingMaterials.exactData(draft) else { throw PublishModesError.invalidDraft }
        self.session = session; self.draftID = draftID; source = bytes
    }
    public func isCurrent(session: PublishingSession?, draftID: UUID, draft: ActivityPublishDraft) -> Bool {
        self.session == session && self.draftID == draftID && source == ProjectEditPendingMaterials.exactData(draft)
    }
    public func applying(_ choice: ActivityTemplateChoice, session: PublishingSession?, draftID: UUID,
                         draft: ActivityPublishDraft) throws -> ActivityPublishDraft {
        guard choice.availability == .available, isCurrent(session: session, draftID: draftID, draft: draft) else { throw PublishModesError.conflict }
        var next = draft; next.playTemplateID = choice.id; return next
    }
}
