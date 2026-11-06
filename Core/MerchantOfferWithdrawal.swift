import Foundation

/// C8: exiting one's own ordinary chapter supply via `POST /api/coop/offer/withdraw`.
/// Backend contract (hengyin@f4299a64): only the owning merchant's ordinary
/// `FREE_EXPLORE` (productType 2), non-circle, non-terminal, currently active
/// (offer status 1) supply may exit for the first time. A supply is only
/// *withdrawn* when its readback row has status 0 with a non-blank withdraw
/// reason; status 0 without a reason is merely deactivated. Existing orders,
/// fulfilment receivables and redemption facts are retained; there is no
/// automatic refund or dissolution. This module never submits in production:
/// execution is injected, and the shipped executor is dormant.
public enum MerchantOfferWithdrawalFailure: Error, Equatable {
    case invalid(String), malformed, denied, changedSession, conflict, disabled, storage, unknown, locked
    case rejected(code: Int, message: String?)
    public var key: String {
        switch self {
        case .invalid: return "merchant.offerWithdrawal.invalid"
        case .malformed: return "merchant.offerWithdrawal.malformed"
        case .denied: return "merchant.offerWithdrawal.denied"
        case .changedSession: return "merchant.offerWithdrawal.sessionChanged"
        case .conflict: return "merchant.offerWithdrawal.conflict"
        case .disabled: return "merchant.offerWithdrawal.disabled"
        case .storage: return "merchant.offerWithdrawal.storage"
        case .unknown: return "merchant.offerWithdrawal.unknown"
        case .locked: return "merchant.offerWithdrawal.locked"
        case .rejected: return "merchant.offerWithdrawal.rejected"
        }
    }
}

/// Exit reason: trimmed, 1...500 in UTF-16 units, matching the backend
/// `String.trim()` + `length() > 500` check. The trimmed value is what is sent.
public struct MerchantOfferWithdrawalReason: Equatable, Sendable {
    public static let maximumLength = 500
    public let value: String
    public init(raw: String) throws {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf16.count <= Self.maximumLength else {
            throw MerchantOfferWithdrawalFailure.invalid("reason")
        }
        value = trimmed
    }
    public static func length(of raw: String) -> Int {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count
    }
    public static func isValid(raw: String) -> Bool { (try? MerchantOfferWithdrawalReason(raw: raw)) != nil }
}

/// Wire shape of `POST api/coop/offer/withdraw`: exactly `offerId` and
/// `reason`. There is deliberately no requestId or merchant identity field;
/// the backend resolves the owner from the authenticated principal.
public struct MerchantOfferWithdrawalRequest: Equatable, Sendable {
    public static let path = "api/coop/offer/withdraw"
    public let offerID: Int
    public let reason: MerchantOfferWithdrawalReason
    public init(offerID: Int, reason: MerchantOfferWithdrawalReason) throws {
        guard offerID > 0 else { throw MerchantOfferWithdrawalFailure.invalid("offerId") }
        self.offerID = offerID; self.reason = reason
    }
    public init(offerID: Int, rawReason: String) throws {
        try self.init(offerID: offerID, reason: MerchantOfferWithdrawalReason(raw: rawReason))
    }
    public var fields: [String: MerchantContentValue] {
        ["offerId": .integer(offerID), "reason": .string(reason.value)]
    }
    public func canonicalJSON() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(fields)
    }
}

/// The withdraw response only carries the `enrollmentPaused` hint. It is not
/// a receipt: confirmation always comes from the `mine` readback below.
public struct MerchantOfferWithdrawalResponseHint: Equatable, Sendable {
    public let enrollmentPaused: Bool?
    public init(enrollmentPaused: Bool?) { self.enrollmentPaused = enrollmentPaused }
    public init(data: MerchantContentValue) throws {
        guard data.object != nil else { throw MerchantOfferWithdrawalFailure.malformed }
        if let flag = data["enrollmentPaused"].flag { enrollmentPaused = flag }
        else if let number = data["enrollmentPaused"].integer, [0, 1].contains(number) { enrollmentPaused = number == 1 }
        else if case .null = data["enrollmentPaused"] { enrollmentPaused = nil }
        else { throw MerchantOfferWithdrawalFailure.malformed }
    }
}

/// Server-derived supply state on a `mine` row. `WITHDRAWN` requires a
/// non-blank withdraw reason on the server; `INACTIVE` is a deactivation,
/// never a withdrawal.
public enum MerchantOfferSupplyState: Equatable, Sendable {
    case none, active, inactive, withdrawn, expired, unknown
    public init(raw: String?) {
        switch raw {
        case "NONE": self = .none
        case "ACTIVE": self = .active
        case "INACTIVE": self = .inactive
        case "WITHDRAWN": self = .withdrawn
        case "EXPIRED": self = .expired
        default: self = .unknown
        }
    }
}

public enum MerchantOfferWithdrawalIneligibility: Equatable, Sendable {
    case missingOffer, alreadyWithdrawn(serverReason: String), deactivatedNotWithdrawn
    case circleSupply, notOrdinaryFreeExplore, topicTerminal, stateUnconfirmed, productUnconfirmed, lifecycleUnconfirmed
}

/// One of the account's own chapter supplies, projected from its `mine`
/// application row plus the topic detail that proves product type and
/// lifecycle. IDs are never inferred across domains.
public struct MerchantOfferWithdrawalSubject: Equatable, Sendable {
    public static let ordinaryFreeExploreProductType = 2
    public static let terminalLifecycles: Set<Int> = [5, 6] // SETTLING, CLOSED
    public static let knownLifecycles: Set<Int> = [0, 1, 2, 3, 4, 5, 6, 7]

    public let offerID: Int?
    public let applicationID: Int?, chapterID: Int?, topicID: Int?
    public let chapterName: String?, topicName: String?
    public let state: MerchantOfferSupplyState
    public let offerActive: Bool?
    public let serverWithdrawReason: String?
    public let circleThemeCode: String?
    public let productType: Int?, lifecycle: Int?
    /// Whether the chapter is flagged required when known. A required chapter
    /// (or an invalidated supply review) can pause new enrolment on exit;
    /// unknown is disclosed as "may pause", never as "will not pause".
    public let chapterRequired: Bool?

    public init(mineRow: MerchantContentValue, topic: MerchantContentValue? = nil, chapterRequired: Bool? = nil) {
        offerID = mineRow["offerId"].safeInteger.flatMap { $0 > 0 ? $0 : nil }
        applicationID = mineRow["id"].safeInteger.flatMap { $0 > 0 ? $0 : nil }
        chapterID = mineRow["chapterId"].safeInteger.flatMap { $0 > 0 ? $0 : nil }
        topicID = mineRow["topicId"].safeInteger.flatMap { $0 > 0 ? $0 : nil }
        chapterName = mineRow["chapterName"].text.flatMap { $0.isEmpty ? nil : $0 }
        topicName = mineRow["topicName"].text.flatMap { $0.isEmpty ? nil : $0 }
        state = MerchantOfferSupplyState(raw: mineRow["offerState"].text)
        if let flag = mineRow["offerActive"].flag { offerActive = flag }
        else if let number = mineRow["offerActive"].integer, [0, 1].contains(number) { offerActive = number == 1 }
        else { offerActive = nil }
        let reason = mineRow["offerWithdrawReason"].text?.trimmingCharacters(in: .whitespacesAndNewlines)
        serverWithdrawReason = (reason?.isEmpty == false) ? reason : nil
        let circle = (topic?["circleThemeCode"].text ?? mineRow["circleThemeCode"].text)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        circleThemeCode = (circle?.isEmpty == false) ? circle : nil
        productType = (topic?["productType"] ?? mineRow["productType"]).safeInteger
        lifecycle = (topic?["lifecycle"] ?? mineRow["lifecycle"]).safeInteger
        self.chapterRequired = chapterRequired
    }

    public var isCircleSupply: Bool { circleThemeCode != nil }
    /// Only a first exit of a currently active, ordinary, non-circle,
    /// non-terminal supply is eligible. Every unknown fails closed.
    public var ineligibility: MerchantOfferWithdrawalIneligibility? {
        if state == .withdrawn { return .alreadyWithdrawn(serverReason: serverWithdrawReason ?? "") }
        if isCircleSupply { return .circleSupply }
        guard offerID != nil else { return .missingOffer }
        guard state == .active, offerActive == true else {
            return state == .inactive ? .deactivatedNotWithdrawn : .stateUnconfirmed
        }
        guard let productType else { return .productUnconfirmed }
        guard productType == Self.ordinaryFreeExploreProductType else { return .notOrdinaryFreeExplore }
        guard let lifecycle, Self.knownLifecycles.contains(lifecycle) else { return .lifecycleUnconfirmed }
        guard !Self.terminalLifecycles.contains(lifecycle) else { return .topicTerminal }
        return nil
    }
    public var isEligible: Bool { ineligibility == nil }
}

/// Impact facts the confirmation screen must not omit. Retention facts are
/// unconditional. Enrolment may still pause when the chapter is not required,
/// so the disclosure stays until a fact excludes both causes.
public struct MerchantOfferWithdrawalImpact: Equatable, Sendable {
    public let mayPauseNewEnrolment: Bool
    public let retainsOrdersFulfilmentAndRedemption = true
    public let automaticRefundOrDissolution = false
    public let mayInvalidateSupplyReviewAndPublication = true
    public let mayNotifyParticipantsAndOwner = true
    public init(subject: MerchantOfferWithdrawalSubject) {
        // Backend pauses when the chapter is required OR its review was invalidated.
        // `chapterRequired == false` does not exclude that, so the disclosure stays
        // until an authoritative fact says both are clear. No such fact is on this row.
        mayPauseNewEnrolment = true
        _ = subject
    }
}

/// Precise readback by the original offerId on the account's own `mine` rows.
public enum MerchantOfferWithdrawalReadback: Equatable, Sendable {
    case confirmed(serverReason: String, matchesRequestedReason: Bool)
    case notWithdrawn(state: MerchantOfferSupplyState)
    case inconsistentWithdrawnWithoutReason
    case offerMissing
    case ambiguousMultipleRows

    public static func verify(offerID: Int, requestedReason: String?, mineRows: [MerchantContentValue]) -> MerchantOfferWithdrawalReadback {
        let matches = mineRows.filter { $0["offerId"].safeInteger == offerID }
        guard !matches.isEmpty else { return .offerMissing }
        guard matches.count == 1 else { return .ambiguousMultipleRows }
        let row = matches[0]
        let state = MerchantOfferSupplyState(raw: row["offerState"].text)
        guard state == .withdrawn else { return .notWithdrawn(state: state) }
        let server = row["offerWithdrawReason"].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !server.isEmpty else { return .inconsistentWithdrawnWithoutReason }
        let requested = requestedReason?.trimmingCharacters(in: .whitespacesAndNewlines)
        return .confirmed(serverReason: server, matchesRequestedReason: requested.map { $0 == server } ?? false)
    }
}
