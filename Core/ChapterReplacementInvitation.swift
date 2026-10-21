import Foundation

/// C9 host-side chapter replacement invitation (contract `hengyin@f4299a6`, read-only basis).
///
/// Wire facts used here are only those stated for C9:
/// - `POST api/merchant/chapter-application/invitable` with required `topicId` and
///   optional `latitude`/`longitude`; a real candidate row supplies
///   `merchantMemberId` + `chapterId` + `replacementOfOfferId` for the invite.
/// - `POST api/merchant/chapter-application/invite` submits exactly those three IDs plus
///   optional `message`/`scope`. There is no `requestId`.
/// - Success creates only `source = INVITE` / `status = PENDING`. It never auto-accepts,
///   never fills the supply, and never touches payment/refund.
///
/// Baseline divergence, reported not hidden: invitable candidate rows are
/// `memberId` + `chapterId` + `replacementOfOfferId`. `merchantMemberId` is accepted
/// only when it agrees with `memberId`. Owner readback uses `merchantId` as the member
/// id and never that alias. Disagreeing ids fail closed. No other field names are invented.
public enum ChapterReplacementInvitationFailure: Error, Equatable {
    case invalid, malformed, denied, notTopicPublisher, vacancyIneligible
    case candidateMismatch, originalMerchant, alreadyReplaced, duplicateReadback
    case stateMismatch, notFound, unknown, staleTopic, busy, noSelection
}

public enum ChapterReplacementInvitationScope: String, Codable, Equatable, Sendable {
    /// Requires `merchant:project:manage` mapped through a merchant owner (see plan rules).
    case merchant
    /// The signed-in member acting for themself; no merchant scope is sent.
    case currentMember

    public var wireValue: String? {
        switch self {
        case .merchant: return "MERCHANT"
        case .currentMember: return nil
        }
    }
}

public struct ChapterReplacementInvitationCoordinates: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) throws {
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw ChapterReplacementInvitationFailure.invalid
        }
        self.latitude = latitude; self.longitude = longitude
    }
}

public struct ChapterReplacementInvitationInvitableRequest: Equatable, Sendable {
    public static let path = "api/merchant/chapter-application/invitable"
    public let topicID: Int
    /// `nil` is a first-class case: refusing location permission must still allow the query.
    public let coordinates: ChapterReplacementInvitationCoordinates?

    public init(topicID: Int, coordinates: ChapterReplacementInvitationCoordinates? = nil) throws {
        guard topicID > 0 else { throw ChapterReplacementInvitationFailure.invalid }
        self.topicID = topicID; self.coordinates = coordinates
    }

    public func fields() -> [String: MerchantContentValue] {
        var fields: [String: MerchantContentValue] = ["topicId": .integer(topicID)]
        if let coordinates {
            fields["latitude"] = .decimal(Decimal(string: String(coordinates.latitude)) ?? .zero)
            fields["longitude"] = .decimal(Decimal(string: String(coordinates.longitude)) ?? .zero)
        }
        return fields
    }
}

/// A withdrawn original supply that left a vacancy. Invariants are enforced at parse
/// time so a plan can never be built from a non-withdrawn or unexplained supply:
/// same-row `topicId`/`chapterId`, `status == 0`, and a non-blank `withdrawReason`.
public struct ChapterReplacementInvitationVacancy: Equatable, Identifiable, Sendable {
    public let offerID: Int
    public let topicID: Int
    public let chapterID: Int
    public let status: Int
    public let withdrawReason: String
    public let originalMerchantMemberID: Int

    public var id: Int { offerID }

    public init(row: MerchantContentValue) throws {
        guard row.object != nil else { throw ChapterReplacementInvitationFailure.malformed }
        // Offer rows in this codebase carry the offer under `offerId` (an application row
        // may also carry its own `id`); `id` is only the fallback primary key.
        guard let offerID = (row["offerId"].integer ?? row["id"].integer), offerID > 0,
              let topicID = row["topicId"].integer, topicID > 0,
              let chapterID = row["chapterId"].integer, chapterID > 0,
              let status = row["status"].integer,
              let original = Self.memberID(in: row), original > 0 else {
            throw ChapterReplacementInvitationFailure.malformed
        }
        let reason = (row["withdrawReason"].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard status == 0, !reason.isEmpty else { throw ChapterReplacementInvitationFailure.vacancyIneligible }
        self.offerID = offerID; self.topicID = topicID; self.chapterID = chapterID
        self.status = status; self.withdrawReason = reason
        self.originalMerchantMemberID = original
    }

    /// Identity-only vacancy for a restored UNKNOWN lock. Not a parsed offer row.
    init(lockedOfferID: Int, topicID: Int, chapterID: Int) {
        offerID = lockedOfferID
        self.topicID = topicID
        self.chapterID = chapterID
        status = 0
        withdrawReason = ""
        originalMerchantMemberID = 0
    }

    /// Offer rows name the original merchant with `merchantMemberId` (alias `memberId`).
    static func memberID(in row: MerchantContentValue) -> Int? {
        let primary = row["merchantMemberId"].integer
        let legacy = row["memberId"].integer
        if let primary, let legacy, primary != legacy { return nil }
        return primary ?? legacy
    }

    /// Invitable candidates: `memberId` + `chapterId` + `replacementOfOfferId`.
    /// `merchantMemberId` is accepted only when it agrees with `memberId`.
    static func candidateMemberID(in row: MerchantContentValue) -> Int? {
        let member = row["memberId"].integer
        let alias = row["merchantMemberId"].integer
        if let member, let alias, member != alias { return nil }
        guard let id = member ?? alias, id > 0 else { return nil }
        return id
    }

    /// mine / owner-list / owner-mine `merchantId` is the member id, not the archive id.
    static func ownerMemberID(in row: MerchantContentValue) -> Int? {
        row["merchantId"].integer.flatMap { $0 > 0 ? $0 : nil }
    }

    public static func vacancies(rows: [MerchantContentValue]) -> [ChapterReplacementInvitationVacancy] {
        rows.compactMap { try? ChapterReplacementInvitationVacancy(row: $0) }
    }
}

public struct ChapterReplacementInvitationCandidate: Equatable, Identifiable, Sendable {
    public let merchantMemberID: Int
    public let chapterID: Int
    public let replacementOfOfferID: Int
    public let displayName: String?

    public var id: String { "\(merchantMemberID):\(chapterID):\(replacementOfOfferID)" }

    public init(row: MerchantContentValue) throws {
        guard row.object != nil,
              let member = ChapterReplacementInvitationVacancy.candidateMemberID(in: row), member > 0,
              let chapterID = row["chapterId"].integer, chapterID > 0,
              let replacement = row["replacementOfOfferId"].integer, replacement > 0 else {
            throw ChapterReplacementInvitationFailure.malformed
        }
        merchantMemberID = member; chapterID = chapterID; replacementOfOfferID = replacement
        let name = (row["merchantName"].text ?? row["name"].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        displayName = name.isEmpty ? nil : name
    }

    init(merchantMemberID: Int, chapterID: Int, replacementOfOfferID: Int) {
        self.merchantMemberID = merchantMemberID
        self.chapterID = chapterID
        self.replacementOfOfferID = replacementOfOfferID
        displayName = nil
    }

    public static func candidates(rows: [MerchantContentValue], vacancy: ChapterReplacementInvitationVacancy) -> [ChapterReplacementInvitationCandidate] {
        rows.compactMap { try? ChapterReplacementInvitationCandidate(row: $0) }
            .filter { $0.chapterID == vacancy.chapterID && $0.replacementOfOfferID == vacancy.offerID }
    }
}

/// One already-visible chapter application, used only to reject duplicates before sending.
public struct ChapterReplacementInvitationExisting: Equatable, Sendable {
    public let applicationID: Int
    public let chapterID: Int?
    public let merchantMemberID: Int?
    public let status: Int
    public let replacementOfOfferID: Int?

    public init(row: MerchantContentValue) throws {
        guard row.object != nil, let id = row["id"].integer, id > 0,
              let status = row["status"].integer else { throw ChapterReplacementInvitationFailure.malformed }
        applicationID = id; status = status
        chapterID = row["chapterId"].integer
        merchantMemberID = ChapterReplacementInvitationVacancy.ownerMemberID(in: row)
        replacementOfOfferID = row["replacementOfOfferId"].integer
    }

    /// Pending (0) or approved (1) applications block a new replacement invitation.
    public var blocksReplacement: Bool { status == 0 || status == 1 }

    public static func existing(rows: [MerchantContentValue]) -> [ChapterReplacementInvitationExisting] {
        rows.compactMap { try? ChapterReplacementInvitationExisting(row: $0) }
    }
}

/// Proof the host must supply. This module does not fetch it.
/// C7 composition has to pass a fresh topic-publisher read for `topicID`/`actorAccountID`
/// plus `MerchantAccess.isOwner && allows(.projects)`. A constant `true` is not a proof.
public struct ChapterReplacementInvitationPublisherProof: Equatable, Sendable {
    public let topicID: Int
    public let actorAccountID: Int
    public let isFreshTopicPublisher: Bool
    public let projectManageOwnerMapped: Bool

    public init(topicID: Int, actorAccountID: Int, isFreshTopicPublisher: Bool, projectManageOwnerMapped: Bool) {
        self.topicID = topicID
        self.actorAccountID = actorAccountID
        self.isFreshTopicPublisher = isFreshTopicPublisher
        self.projectManageOwnerMapped = projectManageOwnerMapped
    }

    public var verified: Bool {
        topicID > 0 && actorAccountID > 0 && isFreshTopicPublisher && projectManageOwnerMapped
    }
}

public struct ChapterReplacementInvitationPlan: Equatable, Sendable {
    public static let invitePath = "api/merchant/chapter-application/invite"
    public let topicID: Int
    public let vacancy: ChapterReplacementInvitationVacancy
    public let candidate: ChapterReplacementInvitationCandidate
    public let scope: ChapterReplacementInvitationScope
    public let actorAccountID: Int
    public let message: String?

    /// Full target tuple used for UNKNOWN readback. Includes `replacementOfOfferId`;
    /// a tuple without it is never sufficient proof that this invite landed.
    public var targetTuple: String {
        "topic:\(topicID)|chapter:\(candidate.chapterID)|merchantMember:\(candidate.merchantMemberID)|replacementOfOffer:\(candidate.replacementOfOfferID)|scope:\(scope.wireValue ?? "SELF")"
    }

    public static func make(topicID: Int,
                            scope: ChapterReplacementInvitationScope,
                            actorAccountID: Int,
                            merchantAccess: MerchantAccess?,
                            publisherProof: ChapterReplacementInvitationPublisherProof,
                            vacancy: ChapterReplacementInvitationVacancy,
                            candidate: ChapterReplacementInvitationCandidate,
                            existing: [ChapterReplacementInvitationExisting],
                            message: String = "") throws -> ChapterReplacementInvitationPlan {
        guard topicID > 0, actorAccountID > 0 else { throw ChapterReplacementInvitationFailure.invalid }
        // The server requires the real topic publisher. A `COOP_MANAGE`-style employee
        // who is not the publisher must not invite on the host's behalf, in either scope.
        guard publisherProof.topicID == topicID, publisherProof.actorAccountID == actorAccountID,
              publisherProof.verified else { throw ChapterReplacementInvitationFailure.notTopicPublisher }
        if scope == .merchant {
            // PROJECT_MANAGE (`merchant:project:manage`) mapped to the merchant owner.
            // A manager/marketing role with the raw permission string is not enough here
            // because `MerchantAccess` only retains modelled permissions; ownership is
            // the additional owner mapping required by C9.
            guard let access = merchantAccess, access.active, access.isOwner,
                  access.allows(.projects), (access.merchantID ?? 0) > 0 else {
                throw ChapterReplacementInvitationFailure.denied
            }
        }
        guard vacancy.topicID == topicID else { throw ChapterReplacementInvitationFailure.candidateMismatch }
        guard vacancy.status == 0, !vacancy.withdrawReason.isEmpty else { throw ChapterReplacementInvitationFailure.vacancyIneligible }
        guard candidate.chapterID == vacancy.chapterID,
              candidate.replacementOfOfferID == vacancy.offerID else { throw ChapterReplacementInvitationFailure.candidateMismatch }
        guard candidate.merchantMemberID != vacancy.originalMerchantMemberID else { throw ChapterReplacementInvitationFailure.originalMerchant }
        for row in existing where row.blocksReplacement {
            if row.replacementOfOfferID == vacancy.offerID { throw ChapterReplacementInvitationFailure.alreadyReplaced }
            if row.merchantMemberID == candidate.merchantMemberID, row.chapterID == candidate.chapterID {
                throw ChapterReplacementInvitationFailure.alreadyReplaced
            }
        }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return ChapterReplacementInvitationPlan(topicID: topicID, vacancy: vacancy, candidate: candidate,
                                                scope: scope, actorAccountID: actorAccountID,
                                                message: trimmed.isEmpty ? nil : trimmed)
    }

    /// Re-checked immediately before dispatch: a topic change invalidates the plan.
    public func validateCurrent(topicID: Int, actorAccountID: Int) throws {
        guard topicID == self.topicID, actorAccountID == self.actorAccountID else {
            throw ChapterReplacementInvitationFailure.staleTopic
        }
    }

    public func inviteFields() -> [String: MerchantContentValue] {
        var fields: [String: MerchantContentValue] = [
            "chapterId": .integer(candidate.chapterID),
            "merchantMemberId": .integer(candidate.merchantMemberID),
            "replacementOfOfferId": .integer(candidate.replacementOfOfferID),
        ]
        if let message { fields["message"] = .string(message) }
        if let scope = scope.wireValue { fields["scope"] = .string(scope) }
        return fields
    }
}

/// What sending will and will not do, shown to the host before dispatch.
public struct ChapterReplacementInvitationImpact: Equatable, Sendable {
    public let plan: ChapterReplacementInvitationPlan
    public var createsPendingInvite: Bool { true }
    /// Deliberate contract boundaries: no automatic acceptance, supply fill, or money move.
    public var autoAccepts: Bool { false }
    public var fillsSupply: Bool { false }
    public var triggersPaymentOrRefund: Bool { false }

    public init(plan: ChapterReplacementInvitationPlan) { self.plan = plan }
}

public struct ChapterReplacementInvitationOwnerListRequest: Equatable, Sendable {
    public static let path = "api/merchant/chapter-application/owner-list"
    public let topicID: Int
    public let scope: ChapterReplacementInvitationScope
    public init(topicID: Int, scope: ChapterReplacementInvitationScope) throws {
        guard topicID > 0 else { throw ChapterReplacementInvitationFailure.invalid }
        self.topicID = topicID; self.scope = scope
    }
    public func fields() -> [String: MerchantContentValue] {
        var fields: [String: MerchantContentValue] = ["topicId": .integer(topicID)]
        if let scope = scope.wireValue { fields["scope"] = .string(scope) }
        return fields
    }
}

public struct ChapterReplacementInvitationOwnerMineRequest: Equatable, Sendable {
    public static let path = "api/merchant/chapter-application/owner-mine"
    public let scope: ChapterReplacementInvitationScope
    public init(scope: ChapterReplacementInvitationScope) { self.scope = scope }
    public func fields() -> [String: MerchantContentValue] {
        var fields: [String: MerchantContentValue] = [:]
        if let scope = scope.wireValue { fields["scope"] = .string(scope) }
        return fields
    }
}

public struct ChapterReplacementInvitationVerified: Equatable, Sendable {
    public let applicationID: Int?
    public let status: Int
    public let plan: ChapterReplacementInvitationPlan
}

public enum ChapterReplacementInvitationReadback {
    /// Exact-tuple verification over `owner-list` / `owner-mine` rows.
    /// `source == 1` is the already-shipped invitation marker (merchant applications
    /// are `source == 0`); creation success is only `status == 0` (PENDING).
    public static func verify(rows: [MerchantContentValue], plan: ChapterReplacementInvitationPlan) throws -> ChapterReplacementInvitationVerified {
        var matches: [ChapterReplacementInvitationVerified] = []
        var sawTupleWithWrongState = false
        for row in rows where row.object != nil {
            guard ChapterReplacementInvitationVacancy.ownerMemberID(in: row) == plan.candidate.merchantMemberID,
                  row["chapterId"].integer == plan.candidate.chapterID,
                  row["replacementOfOfferId"].integer == plan.candidate.replacementOfOfferID,
                  row["topicId"].integer == plan.topicID,
                  row["source"].integer == 1 else { continue }
            guard row["status"].integer == 0 else { sawTupleWithWrongState = true; continue }
            matches.append(.init(applicationID: row["id"].integer, status: 0, plan: plan))
        }
        if matches.count > 1 { throw ChapterReplacementInvitationFailure.duplicateReadback }
        if let match = matches.first { return match }
        if sawTupleWithWrongState { throw ChapterReplacementInvitationFailure.stateMismatch }
        throw ChapterReplacementInvitationFailure.notFound
    }

    public static func verify(ownerList: [MerchantContentValue], ownerMine: [MerchantContentValue],
                              plan: ChapterReplacementInvitationPlan) throws -> ChapterReplacementInvitationVerified {
        // Either leg alone can prove the tuple; both legs together must not double-count
        // the same application as a duplicate.
        let combined = ownerList + ownerMine.filter { mine in
            !ownerList.contains { $0["id"].integer != nil && $0["id"].integer == mine["id"].integer }
        }
        return try verify(rows: combined, plan: plan)
    }
}
