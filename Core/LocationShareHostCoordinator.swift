import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Reform plan v9 §21 / W13.5–W13.8 host state for the existing mini-program per-session
/// approximate roam presence toggle (`/api/roam/presence-visibility`, consent `roam-presence-v1`).
/// Gated default-off until the endpoint is added to a reviewed allowlist.
public struct RoamPresenceApproximateToggleState: Equatable {
    public static let defaultEndpointAllowlisted = false

    public enum Phase: Equatable {
        case off
        case pendingEnable(sessionID: Int)
        case confirmedVisible(sessionID: Int)
        case unknown(sessionID: Int)
    }

    public private(set) var phase: Phase = .off
    public private(set) var sessionID: Int?
    public private(set) var consentAccepted = false
    private var stoppedSessionIDs: Set<Int> = []

    public init() {}

    public var isVisible: Bool {
        if case .confirmedVisible = phase { return true }
        return false
    }

    public mutating func setConsentAccepted(_ accepted: Bool) {
        consentAccepted = accepted
        if !accepted, case .pendingEnable = phase {
            phase = .off
        }
    }

    /// Builds a read request only when the endpoint is explicitly allowlisted.
    public func makeReadRequest(
        baseURL: URL,
        sessionID: Int,
        endpointAllowlisted: Bool = Self.defaultEndpointAllowlisted
    ) throws -> URLRequest {
        guard endpointAllowlisted else { throw LocationShareFailure.featureDisabled }
        return try RoamPresenceVisibilityContract.readRequest(baseURL: baseURL, sessionID: sessionID)
    }

    /// Validates session and consent before forming the POST request, gated by `endpointAllowlisted`.
    public mutating func beginEnable(
        baseURL: URL,
        sessionID: Int?,
        endpointAllowlisted: Bool = Self.defaultEndpointAllowlisted
    ) throws -> URLRequest {
        let request = try RoamPresenceVisibilityContract.changeRequest(
            baseURL: baseURL,
            sessionID: sessionID,
            visible: true,
            consentAccepted: consentAccepted
        )
        guard endpointAllowlisted else { throw LocationShareFailure.featureDisabled }
        guard let validSessionID = sessionID, validSessionID > 0 else {
            throw LocationShareFailure.consentIncomplete
        }
        stoppedSessionIDs.remove(validSessionID)
        self.sessionID = validSessionID
        phase = .pendingEnable(sessionID: validSessionID)
        return request
    }

    /// Turning off is immediate locally and never requires prior consent.
    public mutating func stopAndMakeDisableRequest(
        baseURL: URL,
        endpointAllowlisted: Bool = Self.defaultEndpointAllowlisted
    ) throws -> URLRequest {
        let activeSession = sessionID
        if let activeSession {
            stoppedSessionIDs.insert(activeSession)
        }
        phase = .off
        sessionID = nil
        let request = try RoamPresenceVisibilityContract.changeRequest(
            baseURL: baseURL,
            sessionID: activeSession,
            visible: false,
            consentAccepted: false
        )
        guard endpointAllowlisted else { throw LocationShareFailure.featureDisabled }
        return request
    }

    /// Mini-program parity: enabling is confirmed only when the change echo and a fresh readback
    /// both decode to `true` and no stop occurred in the meantime.
    public mutating func finishEnable(
        sessionID: Int,
        changeResponseData: Data,
        readbackResponseData: Data
    ) {
        guard !stoppedSessionIDs.contains(sessionID),
              case .pendingEnable(let pendingSession) = phase,
              pendingSession == sessionID else {
            return
        }
        let changeEcho = RoamPresenceVisibilityContract.decode(changeResponseData)
        let readback = RoamPresenceVisibilityContract.decode(readbackResponseData)
        if RoamPresenceVisibilityContract.confirmedEnabled(changeEcho: changeEcho, readback: readback) == true {
            phase = .confirmedVisible(sessionID: sessionID)
        } else if changeEcho == false && readback == false {
            phase = .off
        } else {
            phase = .unknown(sessionID: sessionID)
        }
    }

    /// Applies a single GET readback response for the active session.
    public mutating func applyReadback(sessionID: Int, data: Data) {
        guard !stoppedSessionIDs.contains(sessionID), self.sessionID == sessionID || self.sessionID == nil else {
            return
        }
        self.sessionID = sessionID
        guard let decoded = RoamPresenceVisibilityContract.decode(data) else {
            phase = .unknown(sessionID: sessionID)
            return
        }
        phase = decoded ? .confirmedVisible(sessionID: sessionID) : .off
    }

    public mutating func endForSessionChange() {
        if let sessionID {
            stoppedSessionIDs.insert(sessionID)
        }
        if case .pendingEnable(let pending) = phase {
            stoppedSessionIDs.insert(pending)
        }
        phase = .off
        sessionID = nil
        consentAccepted = false
    }
}

/// Coordinates W13.5–W13.8 owner location sharing (`LocationShareDraft`, `LocationShareOwnerState`),
/// receiver peer location board (`SharedPeerLocationBoard`), and per-session approximate roam
/// presence (`RoamPresenceApproximateToggleState`).
@MainActor @Observable public final class LocationShareHostCoordinator {
    public static let osPermissionIsNotSharingKey = "mapCore.share.permissionIsNotSharing"

    public private(set) var draft = LocationShareDraft()
    public private(set) var ownerState = LocationShareOwnerState()
    public private(set) var peerBoard = SharedPeerLocationBoard()
    public private(set) var roamPresence = RoamPresenceApproximateToggleState()
    public var showsSharingExplainer = false
    public private(set) var osLocationAuthorized: Bool

    public init(osLocationAuthorized: Bool = false) {
        self.osLocationAuthorized = osLocationAuthorized
    }

    /// W13.5: Granting OS location permission never enables location sharing or presence visibility.
    public func updateOSLocationAuthorization(_ authorized: Bool) {
        osLocationAuthorized = authorized
        if !authorized {
            ownerState.endForSessionChange()
            roamPresence.endForSessionChange()
        }
    }

    public var isPreciseSharingFeatureEnabled: Bool {
        LocationShareFeature.preciseGrantEnabled
    }

    public var isSharingActive: Bool {
        ownerState.isSharing
    }

    public var missingDisclosures: [LocationShareDisclosure] {
        draft.missingDisclosures
    }

    public var canStartPreciseSharing: Bool {
        LocationShareFeature.preciseGrantEnabled &&
            (draft.audience?.isValid == true) &&
            draft.missingDisclosures.isEmpty
    }

    // MARK: - Draft & Disclosure Controls (W13.5)

    public func acknowledge(_ disclosure: LocationShareDisclosure) {
        draft.acknowledge(disclosure)
    }

    public func withdraw(_ disclosure: LocationShareDisclosure) {
        draft.withdraw(disclosure)
    }

    public func acknowledgeAllDisclosures() {
        for disclosure in LocationShareDisclosure.allCases {
            draft.acknowledge(disclosure)
        }
    }

    public func choose(precision: LocationSharePrecision) {
        draft.choose(precision: precision)
    }

    public func choose(audience: LocationShareAudience) {
        draft.choose(audience: audience)
    }

    public func choose(duration: LocationShareDuration) {
        draft.choose(duration: duration)
    }

    /// Attempts to form a `LocationShareGrantRequest` and transition `ownerState` to `.requesting`.
    /// Fails closed with `.featureDisabled` while `LocationShareFeature.preciseGrantEnabled` is false.
    public func startPreciseShareRequest(
        consentVersion: String,
        requestID: UUID = UUID()
    ) throws -> LocationShareGrantRequest {
        let request = try draft.request(consentVersion: consentVersion, requestID: requestID)
        guard ownerState.begin(request) else {
            throw LocationShareFailure.notAuthorized
        }
        return request
    }

    /// Direct owner state transition helper for testing/host state machines (e.g., U04 stop-beats-create).
    @discardableResult
    public func beginOwnerRequest(_ request: LocationShareGrantRequest) -> Bool {
        ownerState.begin(request)
    }

    public func finishOwnerCreate(_ requestID: UUID, grant: LocationShareGrant?) {
        ownerState.finishCreate(requestID, grant: grant)
    }

    public func stopOwnerSharing() {
        ownerState.stop()
    }

    public func finishOwnerRevoke() {
        ownerState.finishRevoke()
    }

    public func expireOwnerIfNeeded(now: Date) {
        ownerState.expireIfNeeded(now: now)
    }

    // MARK: - Receiver Peer Location Board (W13.6–W13.8)

    public func replacePeerGrants(_ incoming: [LocationShareGrant], now: Date) {
        peerBoard.replaceGrants(incoming, now: now)
    }

    public func revokePeerGrant(grantID: String) {
        peerBoard.revoke(grantID: grantID)
    }

    public func applyPeerUpdate(_ update: SharedPeerLocation, now: Date) throws {
        try peerBoard.apply(update, now: now)
    }

    public func isPeerLocationStale(grantID: String, now: Date, maxAge: TimeInterval) -> Bool {
        peerBoard.isStale(grantID: grantID, now: now, maxAge: maxAge)
    }

    // MARK: - Roam Presence Approximate Toggle (W13.5)

    public func setRoamPresenceConsent(_ accepted: Bool) {
        roamPresence.setConsentAccepted(accepted)
    }

    public func makeRoamPresenceReadRequest(
        baseURL: URL,
        sessionID: Int,
        endpointAllowlisted: Bool = RoamPresenceApproximateToggleState.defaultEndpointAllowlisted
    ) throws -> URLRequest {
        try roamPresence.makeReadRequest(
            baseURL: baseURL,
            sessionID: sessionID,
            endpointAllowlisted: endpointAllowlisted
        )
    }

    public func beginRoamPresenceEnable(
        baseURL: URL,
        sessionID: Int?,
        endpointAllowlisted: Bool = RoamPresenceApproximateToggleState.defaultEndpointAllowlisted
    ) throws -> URLRequest {
        try roamPresence.beginEnable(
            baseURL: baseURL,
            sessionID: sessionID,
            endpointAllowlisted: endpointAllowlisted
        )
    }

    public func stopRoamPresence(
        baseURL: URL,
        endpointAllowlisted: Bool = RoamPresenceApproximateToggleState.defaultEndpointAllowlisted
    ) throws -> URLRequest {
        try roamPresence.stopAndMakeDisableRequest(
            baseURL: baseURL,
            endpointAllowlisted: endpointAllowlisted
        )
    }

    public func finishRoamPresenceEnable(
        sessionID: Int,
        changeResponseData: Data,
        readbackResponseData: Data
    ) {
        roamPresence.finishEnable(
            sessionID: sessionID,
            changeResponseData: changeResponseData,
            readbackResponseData: readbackResponseData
        )
    }

    // MARK: - Session Change Reset (W13.8)

    /// Ends owner sharing, clears peer board grants/locations, resets roam presence visibility,
    /// and clears in-memory explainer disclosures on account/session/team change.
    public func handleSessionChange() {
        ownerState.endForSessionChange()
        roamPresence.endForSessionChange()
        peerBoard.replaceGrants([], now: .distantFuture)
        draft = LocationShareDraft()
        showsSharingExplainer = false
    }
}
