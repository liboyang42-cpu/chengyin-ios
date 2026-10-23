import Foundation

/// Published ordinary city-orienteering catalog row. Growth rank, free exploration,
/// GPS samples and cancelled random matchmaking are never selectable courses.
public struct OrdinaryCityCourseRecord: Equatable, Sendable, Decodable {
    public let courseID: Int
    public let topicID: Int
    public let productType: Int
    public let publicationStatus: String
    public let kind: String
    public let cityTimeZoneIdentifier: String
    public let publishedRuleVersionID: String
    public let safetyVersionID: String
    public let participationMode: String
    public let requiredClubIDs: [Int]
    public let matchmakingStatus: String?
    public let latitude: Double?
    public let longitude: Double?
    public let accuracyMeters: Double?
    enum CodingKeys: String, CodingKey {
        case courseId, topicId, productType, publicationStatus, kind, cityTimeZone
        case publishedRuleVersionId, safetyVersionId, participationMode, requiredClubIds
        case matchmakingStatus, latitude, longitude, accuracyMeters
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        courseID = try c.decode(Int.self, forKey: .courseId)
        topicID = try c.decode(Int.self, forKey: .topicId)
        productType = try c.decode(Int.self, forKey: .productType)
        publicationStatus = try c.decode(String.self, forKey: .publicationStatus)
        kind = try c.decode(String.self, forKey: .kind)
        cityTimeZoneIdentifier = try c.decode(String.self, forKey: .cityTimeZone)
        publishedRuleVersionID = try c.decode(String.self, forKey: .publishedRuleVersionId)
        safetyVersionID = try c.decode(String.self, forKey: .safetyVersionId)
        participationMode = try c.decode(String.self, forKey: .participationMode)
        requiredClubIDs = try c.decodeIfPresent([Int].self, forKey: .requiredClubIds) ?? []
        matchmakingStatus = try c.decodeIfPresent(String.self, forKey: .matchmakingStatus)
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
        accuracyMeters = try c.decodeIfPresent(Double.self, forKey: .accuracyMeters)
    }
}

/// Frozen pick of one ordinary published city course. Device timezone and GPS are not stored.
public struct OrdinaryCityCourseSelection: Equatable, Sendable {
    public let courseID: Int
    public let topicID: Int
    public let cityTimeZoneIdentifier: String
    public let publishedRuleVersionID: String
    public let safetyVersionID: String
    public let participationMode: String
    public let requiredClubIDs: [Int]
}

/// First-journey bundle: selected course, displayed safety version, TEAM eligibility, frozen start.
public struct OrdinaryCityOrienteeringPreparedStart: Equatable, Sendable {
    public let selection: OrdinaryCityCourseSelection
    public let safety: OrienteeringSafetyVersion
    public let eligibility: TeamClubEligibility
    public let payload: EventScoreStartPayload
}

/// Exclusive ordinary city-orienteering selector. Not Growth personal rank.
public enum OrdinaryCityCourseSelector {
    public static let ordinaryKind = "ORDINARY_CITY_ORIENTEERING"
    public static let publishedStatus = "PUBLISHED"
    public static let teamMode = "TEAM"
    public static let soloMode = "SOLO"
    public static let cancelledMatchmaking = "CANCELLED"
    public static func decodeCatalog(_ data: Data) throws -> [OrdinaryCityCourseRecord] {
        try JSONDecoder().decode([OrdinaryCityCourseRecord].self, from: data)
    }
    public static func isSelectable(_ record: OrdinaryCityCourseRecord) -> Bool {
        guard record.courseID > 0, record.topicID > 0, record.productType == 1,
              record.publicationStatus == publishedStatus, record.kind == ordinaryKind,
              [teamMode, soloMode].contains(record.participationMode),
              versionOK(record.publishedRuleVersionID), versionOK(record.safetyVersionID),
              TimeZone(identifier: record.cityTimeZoneIdentifier) != nil,
              record.matchmakingStatus == nil || record.matchmakingStatus == cancelledMatchmaking,
              record.latitude == nil, record.longitude == nil, record.accuracyMeters == nil,
              record.requiredClubIDs.count <= 32, record.requiredClubIDs.allSatisfy({ $0 > 0 }),
              Set(record.requiredClubIDs).count == record.requiredClubIDs.count else { return false }
        return true
    }
    public static func published(_ catalog: [OrdinaryCityCourseRecord]) -> [OrdinaryCityCourseRecord] {
        catalog.filter(isSelectable)
    }
    public static func select(courseID: Int, from catalog: [OrdinaryCityCourseRecord]) -> OrdinaryCityCourseSelection? {
        let rows = published(catalog).filter { $0.courseID == courseID }
        guard rows.count == 1, let record = rows.first else { return nil }
        return OrdinaryCityCourseSelection(
            courseID: record.courseID, topicID: record.topicID,
            cityTimeZoneIdentifier: record.cityTimeZoneIdentifier,
            publishedRuleVersionID: record.publishedRuleVersionID,
            safetyVersionID: record.safetyVersionID,
            participationMode: record.participationMode,
            requiredClubIDs: record.requiredClubIDs)
    }
    /// Pick ordinary published city course → show safety version → TEAM eligibility → freeze rule version.
    public static func prepareStart(
        courseID: Int, catalog: [OrdinaryCityCourseRecord], actorMemberID: Int,
        actorClubs: [TeamClubMembership], team: TeamRoster?, now: Date
    ) -> OrdinaryCityOrienteeringPreparedStart? {
        guard let selection = select(courseID: courseID, from: catalog),
              let safety = OrienteeringSafetyVersion.display(selection: selection, now: now),
              let eligibility = TeamClubEligibilityProjection.evaluate(
                selection: selection, actorMemberID: actorMemberID, actorClubs: actorClubs, team: team),
              eligibility.isEligible,
              let payload = EventScoreVersionProjection.freeze(selection: selection, safety: safety)
        else { return nil }
        return OrdinaryCityOrienteeringPreparedStart(
            selection: selection, safety: safety, eligibility: eligibility, payload: payload)
    }
}
