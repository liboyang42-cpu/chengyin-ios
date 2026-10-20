import Foundation

public enum ClubOperationsTarget: Hashable { case create; case club(Int) }
public enum ClubOpenSetting: String, CaseIterable {
    case publicVisible, memberPostAllowed, merchantUndertakeOpen
    public var path: String {
        switch self {
        case .publicVisible: return "api/club/open-settings/public-visible"
        case .memberPostAllowed: return "api/club/open-settings/member-post"
        case .merchantUndertakeOpen: return "api/club/open-settings/merchant-coop"
        }
    }
}

/// Canonical values are source values; translate display labels, never wire values.
public enum ClubOperationsCatalog {
    public static let types = ["校园社团", "旅行组织", "兴趣社群", "商业活动组织方", "内容创作团队", "其他"]
    public static let directions = ["轻社交", "深度社交", "RPG体验", "城市定向", "解谜路线", "沉浸式剧情", "运动路线", "艺术体验", "美食体验", "主题聚会"]
}

public struct ClubOperationsDraft: Equatable {
    public var name = "", city = "", description = "", keywords = "", style = "", clubType = ""
    public var activityPrefs: [String] = []
    /// Existing media references are preserved. Native media upload is not enabled.
    public var logo = "", cover = ""
    public var prioritySignupEnabled = false
    public var memberReservedQuota = ""
    public var joinPolicy = 0
    public init() {}
    public init(profile: ClubOperationsProfile) {
        let club = profile.club
        name = club.name; city = club.city ?? club.address ?? ""; description = club.description ?? ""
        keywords = club.keywords ?? ""; style = club.style ?? ""; clubType = club.clubType ?? ""
        activityPrefs = club.activityPrefs; logo = club.logo ?? ""; cover = club.cover ?? ""
        prioritySignupEnabled = profile.prioritySignupEnabled
        memberReservedQuota = profile.memberReservedQuota > 0 ? String(profile.memberReservedQuota) : ""
        joinPolicy = club.joinPolicy
    }
    public func validate(original: ClubOperationsProfile?) throws {
        if let original, !original.club.isOwner {
            let baseline = ClubOperationsDraft(profile: original)
            // Administrators may edit display fields only. Never silently discard
            // an attempted owner-only edit and report it as a successful save.
            guard original.club.viewerIsAdmin,
                  prioritySignupEnabled == baseline.prioritySignupEnabled,
                  memberReservedQuota == baseline.memberReservedQuota,
                  joinPolicy == baseline.joinPolicy else { throw ClubOperationsBlock.forbidden }
        }
        guard !name.trimmed.isEmpty, !city.trimmed.isEmpty else { throw ClubOperationsBlock.requiredFields }
        guard name.count <= 30, city.count <= 20, description.count <= 200, keywords.count <= 60, style.count <= 30 else {
            throw ClubOperationsBlock.textTooLong
        }
        guard (ClubOperationsCatalog.types.contains(clubType) || (original != nil && clubType == (original?.club.clubType ?? ""))),
              Set(activityPrefs).count == activityPrefs.count,
              (activityPrefs == original?.club.activityPrefs || (activityPrefs.count <= 3 && activityPrefs.allSatisfy(ClubOperationsCatalog.directions.contains))) else {
            throw ClubOperationsBlock.invalidSelection
        }
        guard [0, 1].contains(joinPolicy) else { throw ClubOperationsBlock.invalidSelection }
        if !memberReservedQuota.trimmed.isEmpty {
            guard memberReservedQuota.trimmed.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let quota = Int(memberReservedQuota.trimmed), quota >= 0 else { throw ClubOperationsBlock.invalidQuota }
        }
        // Without a verified upload contract, callers cannot introduce media references.
        guard logo == (original?.club.logo ?? ""), cover == (original?.club.cover ?? "") else { throw ClubOperationsBlock.mediaUnavailable }
    }
    func fields(original: ClubOperationsProfile?) throws -> [String: Any] {
        try validate(original: original)
        var value: [String: Any] = ["name": name.trimmed, "logo": logo, "cover": cover,
            "description": description.trimmed, "clubType": clubType, "activityPrefs": activityPrefs.joined(separator: ","),
            "city": city.trimmed, "address": city.trimmed, "keywords": keywords.trimmed, "style": style.trimmed]
        if let original {
            value["id"] = original.club.id
            if original.club.isOwner {
                value["operationConfigUpdated"] = true
                value["prioritySignupEnabled"] = prioritySignupEnabled ? 1 : 0
                value["memberReservedQuota"] = Int(memberReservedQuota.trimmed) ?? 0
                if original.club.joinPolicySupported { value["joinPolicy"] = joinPolicy }
            }
        }
        // memberDiscountPrice is intentionally absent; source preserves its legacy value.
        return value
    }
}

public struct ClubOperationsProfile: Decodable, Equatable {
    public let club: ClubRecord
    public let prioritySignupEnabled: Bool
    public let memberReservedQuota: Int
    /// Missing/unknown openness values remain unknown, so no toggle can be inferred.
    public let publicVisible: Bool?
    public let memberPostAllowed: Bool?
    public let merchantUndertakeOpen: Bool?
    enum CodingKeys: String, CodingKey { case prioritySignupEnabled, memberReservedQuota, publicVisible, memberPostAllowed, merchantUndertakeOpen }
    public init(from decoder: Decoder) throws {
        club = try ClubRecord(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let priority = try c.decodeIfPresent(Int.self, forKey: .prioritySignupEnabled) ?? 0
        memberReservedQuota = try c.decodeIfPresent(Int.self, forKey: .memberReservedQuota) ?? 0
        guard [0, 1].contains(priority), memberReservedQuota >= 0 else { throw APIError.malformedResponse }
        prioritySignupEnabled = priority == 1
        func value(_ key: CodingKeys) throws -> Bool? {
            guard let number = try c.decodeIfPresent(Int.self, forKey: key), [0, 1].contains(number) else { return nil }
            return number == 1
        }
        publicVisible = try value(.publicVisible); memberPostAllowed = try value(.memberPostAllowed)
        merchantUndertakeOpen = try value(.merchantUndertakeOpen)
    }
    public func value(_ setting: ClubOpenSetting) -> Bool? {
        switch setting { case .publicVisible: return publicVisible; case .memberPostAllowed: return memberPostAllowed; case .merchantUndertakeOpen: return merchantUndertakeOpen }
    }
}

public struct ClubOperationsSnapshot: Equatable {
    public let target: ClubOperationsTarget
    public let accountRole: String
    public let ownedClubIDs: [Int]
    public let profile: ClubOperationsProfile?
    public let members: [ClubMember]
    public init(target: ClubOperationsTarget, accountRole: String = "", ownedClubIDs: [Int] = [], profile: ClubOperationsProfile? = nil, members: [ClubMember] = []) {
        self.target = target; self.accountRole = accountRole; self.ownedClubIDs = ownedClubIDs; self.profile = profile; self.members = members
    }
    public var canCreate: Bool { target == .create && accountRole == "club" && ownedClubIDs.count < 2 && ownedClubIDs.allSatisfy({ $0 > 0 }) && Set(ownedClubIDs).count == ownedClubIDs.count }
}

public enum ClubOperationsCommand: Equatable {
    case create(ClubOperationsDraft)
    case update(ClubOperationsDraft, original: ClubOperationsProfile)
    case openSetting(ClubOpenSetting, enabled: Bool, previous: Bool)
    case memberRole(memberID: Int, admin: Bool, previousRole: Int)
    public var path: String {
        switch self {
        case .create: return "api/club/create"
        case .update: return "api/club/update-mine"
        case .openSetting(let setting, _, _): return setting.path
        case .memberRole: return "api/club/set-member-role"
        }
    }
    public func validate(snapshot: ClubOperationsSnapshot, identity: ClubReadIdentity) throws {
        guard let account = identity.accountID, account > 0 else { throw ClubOperationsBlock.signedOut }
        switch self {
        case .create(let draft):
            guard snapshot.canCreate else { throw ClubOperationsBlock.createUnavailable }
            try draft.validate(original: nil)
        case .update(let draft, let original):
            guard snapshot.target == .club(original.club.id), let fresh = snapshot.profile,
                  fresh.club.id == original.club.id, fresh.club.canGovern else { throw ClubOperationsBlock.forbidden }
            // A role change invalidates the whole review, even when both roles
            // can edit display fields. Never silently widen or narrow its scope.
            guard fresh.club.isOwner == original.club.isOwner,
                  fresh.club.viewerIsAdmin == original.club.viewerIsAdmin else { throw ClubOperationsBlock.changed }
            // A newer server edit must not be overwritten by a draft based on older data.
            guard ClubOperationsDraft(profile: fresh) == ClubOperationsDraft(profile: original),
                  fresh.club.joinPolicySupported == original.club.joinPolicySupported else { throw ClubOperationsBlock.changed }
            try draft.validate(original: fresh)
        case .openSetting(let setting, let enabled, let previous):
            guard let profile = snapshot.profile, snapshot.target == .club(profile.club.id), profile.club.isOwner else { throw ClubOperationsBlock.forbidden }
            guard profile.value(setting) == previous, enabled != previous else { throw ClubOperationsBlock.changed }
        case .memberRole(let memberID, let admin, let previous):
            guard let profile = snapshot.profile, snapshot.target == .club(profile.club.id), profile.club.isOwner,
                  memberID != account, Set(snapshot.members.map(\.id)).count == snapshot.members.count,
                  let member = snapshot.members.first(where: { $0.id == memberID }), !member.isOwner else { throw ClubOperationsBlock.forbidden }
            guard [0, 1].contains(previous), member.role == previous, admin != member.isAdmin else { throw ClubOperationsBlock.changed }
            // Source caps non-owner legacy administrators at two. Server still decides.
            if admin && snapshot.members.filter({ $0.isAdmin && !$0.isOwner }).count >= 2 { throw ClubOperationsBlock.adminLimit }
        }
    }
    func fields(snapshot: ClubOperationsSnapshot, identity: ClubReadIdentity) throws -> [String: Any] {
        try validate(snapshot: snapshot, identity: identity)
        switch self {
        case .create(let draft): return try draft.fields(original: nil)
        case .update(let draft, _):
            guard let fresh = snapshot.profile else { throw ClubOperationsBlock.forbidden }
            return try draft.fields(original: fresh)
        case .openSetting(let setting, let enabled, _):
            guard let id = snapshot.profile?.club.id else { throw APIError.invalidRequest }
            return ["id": id, setting.rawValue: enabled ? 1 : 0]
        case .memberRole(let memberID, let admin, _):
            guard let id = snapshot.profile?.club.id else { throw APIError.invalidRequest }
            return ["clubId": id, "memberId": memberID, "role": admin ? 1 : 0]
        }
    }
}

public enum ClubOperationsBlock: Error, Equatable {
    case requiredFields, textTooLong, invalidSelection, invalidQuota, mediaUnavailable
    case signedOut, unavailable, createUnavailable, forbidden, changed, adminLimit, pending, staleReview, cancelled
}
public struct ClubOperationsReceipt: Equatable {
    public let clubID: Int?
    public let message: String?
    public let settingValue: Bool?
    public init(clubID: Int? = nil, message: String? = nil, settingValue: Bool? = nil) {
        self.clubID = clubID; self.message = message; self.settingValue = settingValue
    }
}
public enum ClubOperationsWriteAvailability: Equatable { case unverified, approved, syntheticOnly }
@MainActor public protocol ClubOperationsAccess: AnyObject {
    var identity: ClubReadIdentity? { get }
    var isConfigured: Bool { get }
    var writeAvailability: ClubOperationsWriteAvailability { get }
    func hasPending(target: ClubOperationsTarget) -> Bool
    func snapshot(target: ClubOperationsTarget) async throws -> ClubOperationsSnapshot
    func perform(_ command: ClubOperationsCommand, target: ClubOperationsTarget, expectedIdentity: ClubReadIdentity) async throws -> ClubOperationsReceipt
}
private extension String { var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) } }

public extension ClubOperationsAccess { func hasPending(target: ClubOperationsTarget) -> Bool { false } }

/// Canonical workspace tabs for post-create club routing.
/// Validates `requestedTab` and safely falls back to `.overview` when nil, unknown, or unverified.
public enum ClubWorkspaceTab: String, CaseIterable, Equatable, Sendable {
    case posts
    case events
    case overview
    case manage

    public static let defaultFallback: ClubWorkspaceTab = .overview

    public static func validate(requestedTab: String?) -> ClubWorkspaceTab {
        guard let raw = requestedTab?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty,
              let tab = ClubWorkspaceTab(rawValue: raw) else {
            return .overview
        }
        return tab
    }

    public static func validate(_ requestedTab: ClubWorkspaceTab?) -> ClubWorkspaceTab {
        requestedTab ?? .overview
    }

    public static func resolve(requestedTab: String?, canEnterManagement: Bool = true) -> ClubWorkspaceTab {
        let validated = validate(requestedTab: requestedTab)
        if validated == .manage && !canEnterManagement {
            return .overview
        }
        return validated
    }

    public static func resolve(requestedTab: ClubWorkspaceTab?, canEnterManagement: Bool = true) -> ClubWorkspaceTab {
        let validated = validate(requestedTab)
        if validated == .manage && !canEnterManagement {
            return .overview
        }
        return validated
    }
}

/// Production gate for club creation (`不扩 Club28`).
/// Defaults to closed (`isConfigured == false`, `writeAvailability == .unverified`).
/// Legacy Club28 pauses remain unverified and unchanged; this gate does not claim authorization
/// or full coverage of any legacy Club28 boundary and only checks adapter configuration and write availability.
public struct ClubCreationGate: Equatable, Sendable {
    public static let productionDefault = ClubCreationGate(
        isConfigured: false,
        writeAvailability: .unverified
    )

    public let isConfigured: Bool
    public let writeAvailability: ClubOperationsWriteAvailability

    public init(
        isConfigured: Bool = false,
        writeAvailability: ClubOperationsWriteAvailability = .unverified
    ) {
        self.isConfigured = isConfigured
        self.writeAvailability = writeAvailability
    }

    @MainActor
    public init(access: any ClubOperationsAccess) {
        self.init(
            isConfigured: access.isConfigured,
            writeAvailability: access.writeAvailability
        )
    }

    public var isCreationAllowed: Bool {
        isConfigured && (writeAvailability == .approved || writeAvailability == .syntheticOnly)
    }

    public var isBlocked: Bool {
        !isCreationAllowed
    }

    public var bilingualGateCopy: String {
        if isCreationAllowed {
            return "俱乐部创建门控已开启（不扩 Club28，旧暂停边界保持不变）/ Club creation gate enabled (no Club28 expansion; legacy pauses remain unchanged)."
        }
        return "俱乐部创建门控未开启，暂不可进入俱乐部管理 / Club creation gate is closed; entering Club Management is blocked."
    }
}

/// Verified post-create destination for jumping from club creation into the resolved club workspace tab.
public struct ClubCreateToManageDestination: Equatable, Identifiable, Sendable {
    public let accountId: Int
    public let clubId: Int
    public let tab: ClubWorkspaceTab
    public var id: String { "\(accountId):\(clubId):\(tab.rawValue)" }

    public init(accountId: Int, clubId: Int, tab: ClubWorkspaceTab = .manage) {
        self.accountId = accountId
        self.clubId = clubId
        self.tab = tab
    }

    /// True only when the resolved destination tab is `.manage`.
    /// When `requestedTab` falls back to `.overview` (or another non-manage tab),
    /// navigation must not open the management workspace.
    public var opensManagementWorkspace: Bool {
        tab == .manage
    }

    public var bilingualDestinationLabel: String {
        switch tab {
        case .manage:
            return "已就绪：俱乐部 #\(clubId) 管理工作台（分栏：manage）/ Ready: Club #\(clubId) Management Workspace (Tab: manage)"
        case .overview, .posts, .events:
            return "已就绪：俱乐部 #\(clubId) 俱乐部详情（分栏：\(tab.rawValue)）/ Ready: Club #\(clubId) Club Detail (Tab: \(tab.rawValue))"
        }
    }
}

public enum ClubCreateToManageBlockReason: String, Equatable, Sendable {
    case gateBlocked
    case awaitingConfirmedReceipt
    case readbackFailed
    case accountMismatch
    case clubIdMismatch
}

/// Post-create closure state machine:
/// Confirmed Receipt -> Same-Account Readback Verification (`accountId` & `clubId` match) -> Explicit navigation action.
public struct ClubCreateToManageFlowState: Equatable, Sendable {
    public static let enterManagementButtonTitle = "进入俱乐部管理 / Enter Club Management"

    public var gate: ClubCreationGate
    public var receiptAccountId: Int?
    public var receiptClubId: Int?
    public var currentAccountId: Int?
    public var readbackAccountId: Int?
    public var readbackOwnedClubIds: [Int]
    public var readbackSucceeded: Bool
    public var readbackUnavailable: Bool
    public var requestedTab: String?
    public private(set) var enteredDestination: ClubCreateToManageDestination?

    public init(
        gate: ClubCreationGate = .productionDefault,
        receiptAccountId: Int? = nil,
        receiptClubId: Int? = nil,
        currentAccountId: Int? = nil,
        readbackAccountId: Int? = nil,
        readbackOwnedClubIds: [Int] = [],
        readbackSucceeded: Bool = false,
        readbackUnavailable: Bool = false,
        requestedTab: String? = ClubWorkspaceTab.manage.rawValue,
        enteredDestination: ClubCreateToManageDestination? = nil
    ) {
        self.gate = gate
        self.receiptAccountId = receiptAccountId
        self.receiptClubId = receiptClubId
        self.currentAccountId = currentAccountId
        self.readbackAccountId = readbackAccountId
        self.readbackOwnedClubIds = readbackOwnedClubIds
        self.readbackSucceeded = readbackSucceeded
        self.readbackUnavailable = readbackUnavailable
        self.requestedTab = requestedTab
        self.enteredDestination = enteredDestination
    }

    public var hasConfirmedReceipt: Bool {
        guard !gate.isBlocked,
              let receiptAccountId, receiptAccountId > 0,
              let receiptClubId, receiptClubId > 0 else {
            return false
        }
        return true
    }

    public var isSameAccountVerified: Bool {
        guard let receiptAccountId, receiptAccountId > 0,
              let currentAccountId, currentAccountId == receiptAccountId,
              let readbackAccountId, readbackAccountId == receiptAccountId else {
            return false
        }
        return true
    }

    public var isClubIdVerified: Bool {
        guard readbackSucceeded,
              !readbackUnavailable,
              let receiptClubId, receiptClubId > 0 else {
            return false
        }
        return readbackOwnedClubIds.contains(receiptClubId)
    }

    public var isSameAccountReadbackVerified: Bool {
        hasConfirmedReceipt && isSameAccountVerified && isClubIdVerified
    }

    public var canEnterManagement: Bool {
        isSameAccountReadbackVerified
    }

    public var blockReason: ClubCreateToManageBlockReason? {
        if gate.isBlocked {
            return .gateBlocked
        }
        guard let receiptAccountId, receiptAccountId > 0,
              let receiptClubId, receiptClubId > 0 else {
            return .awaitingConfirmedReceipt
        }
        if currentAccountId != receiptAccountId || (readbackAccountId != nil && readbackAccountId != receiptAccountId) {
            return .accountMismatch
        }
        if readbackUnavailable || !readbackSucceeded || readbackAccountId == nil {
            return .readbackFailed
        }
        if !readbackOwnedClubIds.contains(receiptClubId) {
            return .clubIdMismatch
        }
        return nil
    }

    public var validatedTab: ClubWorkspaceTab {
        ClubWorkspaceTab.resolve(requestedTab: requestedTab, canEnterManagement: canEnterManagement)
    }

    public var actionButtonTitle: String {
        if !canEnterManagement || validatedTab == .manage {
            return Self.enterManagementButtonTitle
        }
        return "进入俱乐部详情（分栏：\(validatedTab.rawValue)）/ Enter Club Detail (Tab: \(validatedTab.rawValue))"
    }

    public var bilingualStatusCopy: String {
        switch blockReason {
        case .gateBlocked:
            return "俱乐部创建门控未开启，暂不可进入俱乐部管理 / Club creation gate is closed; entering Club Management is blocked."
        case .awaitingConfirmedReceipt:
            return "等待俱乐部创建确认回执 / Awaiting confirmed club creation receipt."
        case .accountMismatch:
            return "账号已变更或不匹配，已拦截进入俱乐部管理 / Account mismatch detected; entering Club Management is blocked."
        case .readbackFailed:
            return "同账号回读校验未通过，暂不可进入俱乐部管理 / Same-account readback verification failed; entering Club Management is blocked."
        case .clubIdMismatch:
            return "俱乐部 ID 回读不匹配，已拦截进入俱乐部管理 / Club ID readback mismatch; entering Club Management is blocked."
        case nil:
            let clubId = receiptClubId ?? 0
            return "同账号回读已确认（俱乐部 #\(clubId)），可进入俱乐部管理 / Same-account readback verified (Club #\(clubId)); ready to enter Club Management."
        }
    }

    /// True when an acknowledged write or post-create flow still needs owner-readback recovery
    /// (`readBack()` + `acceptReadback()`) rather than an unverified initial `load()`.
    public func requiresReadbackRecovery(state: ClubOperationsState, hasSnapshot: Bool) -> Bool {
        if case .outcomeUnknown = state { return true }
        if case .acknowledged = state {
            return readbackUnavailable || !hasSnapshot || !readbackSucceeded || readbackAccountId == nil || blockReason == .readbackFailed || blockReason == .clubIdMismatch
        }
        if receiptClubId != nil {
            return readbackUnavailable || !hasSnapshot || !readbackSucceeded || readbackAccountId == nil || blockReason == .readbackFailed || blockReason == .clubIdMismatch
        }
        return readbackUnavailable
    }

    @MainActor
    public mutating func applyConfirmedReceipt(
        state: ClubOperationsState,
        pendingIdentity: ClubReadIdentity?,
        currentIdentity: ClubReadIdentity?,
        access: any ClubOperationsAccess
    ) {
        gate = ClubCreationGate(access: access)
        currentAccountId = currentIdentity?.accountID
        readbackAccountId = nil
        readbackOwnedClubIds = []
        readbackSucceeded = false
        readbackUnavailable = false
        enteredDestination = nil
        if case .acknowledged(let receipt) = state {
            receiptAccountId = pendingIdentity?.accountID ?? currentIdentity?.accountID
            receiptClubId = receipt.clubID
        }
    }

    @MainActor
    @discardableResult
    public mutating func acceptReadback(
        from coordinator: ClubOperationsCoordinator,
        access: any ClubOperationsAccess,
        currentIdentity: ClubReadIdentity?,
        target: ClubOperationsTarget = .create
    ) -> ClubOperationsSnapshot? {
        gate = ClubCreationGate(access: access)
        currentAccountId = currentIdentity?.accountID ?? access.identity?.accountID
        switch coordinator.readback(target: target) {
        case .received(let value):
            var ownedIDs = value.ownedClubIDs
            if let profileID = value.profile?.club.id, !ownedIDs.contains(profileID) {
                ownedIDs.append(profileID)
            }
            readbackUnavailable = false
            readbackAccountId = access.identity?.accountID
            readbackOwnedClubIds = ownedIDs
            readbackSucceeded = access.identity != nil
            if case .acknowledged(let receipt) = coordinator.state(target: target) {
                if receiptAccountId == nil {
                    receiptAccountId = access.identity?.accountID ?? currentIdentity?.accountID
                }
                if let clubID = receipt.clubID {
                    receiptClubId = clubID
                }
            }
            return value
        case .unavailable:
            readbackUnavailable = true
            readbackAccountId = nil
            readbackOwnedClubIds = []
            readbackSucceeded = false
            enteredDestination = nil
            return nil
        default:
            return nil
        }
    }

    @MainActor
    @discardableResult
    public mutating func retryReadback(
        using coordinator: ClubOperationsCoordinator,
        access: any ClubOperationsAccess,
        currentIdentity: ClubReadIdentity?,
        ownerID: UUID,
        target: ClubOperationsTarget = .create
    ) async -> ClubOperationsSnapshot? {
        await coordinator.readBack(target: target, ownerID: ownerID)
        guard access.identity == currentIdentity, !Task.isCancelled else { return nil }
        return acceptReadback(from: coordinator, access: access, currentIdentity: currentIdentity, target: target)
    }

    @discardableResult
    public mutating func enterClubManagement(requestedTab overrideTab: String? = nil) -> ClubCreateToManageDestination? {
        guard canEnterManagement,
              let accountId = receiptAccountId,
              let clubId = receiptClubId else {
            enteredDestination = nil
            return nil
        }
        let resolvedTab = ClubWorkspaceTab.resolve(
            requestedTab: overrideTab ?? requestedTab,
            canEnterManagement: true
        )
        let destination = ClubCreateToManageDestination(accountId: accountId, clubId: clubId, tab: resolvedTab)
        enteredDestination = destination
        return destination
    }
}
