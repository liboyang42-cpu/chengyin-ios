import Foundation

/// Display-only people already included in an allowed activity detail response.
/// Record IDs, owner IDs and missing member IDs never become profile destinations.
public struct ActivityPerson: Equatable {
    public let memberID: Int?
    public let name: String?

    fileprivate init(memberID: Int?, name: String?) {
        self.memberID = memberID
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = trimmed.flatMap { $0.isEmpty ? nil : $0 }
    }
}

public struct ActivityPeople: Decodable, Equatable {
    public let host: ActivityPerson?
    public let participants: [ActivityPerson]
    /// The roster can be partial. Its length is never treated as the total.
    public let registrationCount: Int?
    private enum Keys: String, CodingKey { case collaboratorsList, registrationList, registrationCount }
    private enum PersonKeys: String, CodingKey { case memberId, memberRealName, nickname }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Keys.self)
        let hosts = try values.decodeIfPresent([Host].self, forKey: .collaboratorsList) ?? []
        // The first collaborator is the source's designated host. Do not promote a
        // later collaborator or substitute the activity's owning memberId.
        host = hosts.first?.person
        let preview = try values.decodeIfPresent([Registrant].self, forKey: .registrationList) ?? []
        // This is the public API's bounded preview, never an administrative roster.
        guard preview.count <= 5 else { throw APIError.malformedResponse }
        participants = preview.map(\.person)
        let count = try? values.decode(Int.self, forKey: .registrationCount)
        registrationCount = count.flatMap { $0 >= 0 ? $0 : nil }
    }

    public func contains(memberID: Int) -> Bool {
        guard memberID > 0 else { return false }
        return host?.memberID == memberID || participants.contains { $0.memberID == memberID }
    }

    private struct Host: Decodable {
        let person: ActivityPerson
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: PersonKeys.self)
            person = ActivityPerson(memberID: ActivityPeople.memberID(values),
                                    name: try values.decodeIfPresent(String.self, forKey: .memberRealName))
        }
    }
    private struct Registrant: Decodable {
        let person: ActivityPerson
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: PersonKeys.self)
            person = ActivityPerson(memberID: ActivityPeople.memberID(values),
                                    name: try values.decodeIfPresent(String.self, forKey: .nickname))
        }
    }
    private static func memberID(_ values: KeyedDecodingContainer<PersonKeys>) -> Int? {
        let number = (try? values.decode(Int.self, forKey: .memberId))
            ?? (try? values.decode(String.self, forKey: .memberId)).flatMap(Int.init)
        return number.flatMap { (1...9_007_199_254_740_991).contains($0) ? $0 : nil }
    }
}

/// One read-only navigation selection, bound to the detail and current viewer.
public struct ActivityPersonProfileSelection: Hashable {
    public let activityID: Int
    public let memberID: Int
    public let identity: SocialAccountIdentity
    public let snapshotID: UUID
    public init?(activityID: Int, memberID: Int, people: ActivityPeople, identity: SocialAccountIdentity, snapshotID: UUID) {
        guard activityID > 0, let accountID = identity.accountID, accountID > 0,
              people.contains(memberID: memberID) else { return nil }
        self.activityID = activityID; self.memberID = memberID; self.identity = identity; self.snapshotID = snapshotID
    }
    public func matches(activityID: Int, people: ActivityPeople, identity: SocialAccountIdentity, snapshotID: UUID) -> Bool {
        self.activityID == activityID && self.identity == identity && self.snapshotID == snapshotID
            && people.contains(memberID: memberID)
    }
}
