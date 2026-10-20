import XCTest
@testable import QuestifyCore
#if canImport(Questify)
@testable import Questify
#else
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

public struct ClubCreationGate: Equatable, Sendable {
    public static let club28SubviewLimit = 28
    public static let productionDefault = ClubCreationGate(
        isConfigured: false,
        writeAvailability: .unverified,
        catalogSubviewCount: club28SubviewLimit
    )

    public let isConfigured: Bool
    public let writeAvailability: ClubOperationsWriteAvailability
    public let catalogSubviewCount: Int

    public init(
        isConfigured: Bool = false,
        writeAvailability: ClubOperationsWriteAvailability = .unverified,
        catalogSubviewCount: Int = Self.club28SubviewLimit
    ) {
        self.isConfigured = isConfigured
        self.writeAvailability = writeAvailability
        self.catalogSubviewCount = catalogSubviewCount
    }

    @MainActor
    public init(access: any ClubOperationsAccess) {
        self.init(
            isConfigured: access.isConfigured,
            writeAvailability: access.writeAvailability,
            catalogSubviewCount: Self.club28SubviewLimit
        )
    }

    public var withinClub28Scope: Bool {
        catalogSubviewCount == Self.club28SubviewLimit
    }

    public var isCreationAllowed: Bool {
        isConfigured && withinClub28Scope && (writeAvailability == .approved || writeAvailability == .syntheticOnly)
    }

    public var isBlocked: Bool {
        !isCreationAllowed
    }

    public var bilingualGateCopy: String {
        if isCreationAllowed {
            return "俱乐部创建门控已授权（不扩 Club28）/ Club creation gate authorized (within Club28 scope)."
        }
        return "俱乐部创建门控未开启，暂不可进入俱乐部管理 / Club creation gate is closed; entering Club Management is blocked."
    }
}

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
}

public enum ClubCreateToManageBlockReason: String, Equatable, Sendable {
    case gateBlocked
    case awaitingConfirmedReceipt
    case readbackFailed
    case accountMismatch
    case clubIdMismatch
}

public struct ClubCreateToManageFlowState: Equatable, Sendable {
    public static let enterManagementButtonTitle = "进入俱乐部管理 / Enter Club Management"

    public let gate: ClubCreationGate
    public let receiptAccountId: Int?
    public let receiptClubId: Int?
    public let currentAccountId: Int?
    public let readbackAccountId: Int?
    public let readbackOwnedClubIds: [Int]
    public let readbackSucceeded: Bool
    public let requestedTab: String?
    public private(set) var enteredDestination: ClubCreateToManageDestination?

    public init(
        gate: ClubCreationGate = .productionDefault,
        receiptAccountId: Int? = nil,
        receiptClubId: Int? = nil,
        currentAccountId: Int? = nil,
        readbackAccountId: Int? = nil,
        readbackOwnedClubIds: [Int] = [],
        readbackSucceeded: Bool = false,
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
        if !readbackSucceeded || readbackAccountId == nil {
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
#endif

@MainActor
final class ClubCreateToManageFlowTests: XCTestCase {
    private func validCreateDraft() -> ClubOperationsDraft {
        var draft = ClubOperationsDraft()
        draft.name = "Chengyin Urban Explorers"
        draft.city = "Shanghai"
        draft.clubType = "兴趣社群"
        draft.activityPrefs = ["轻社交"]
        return draft
    }

    func testProductionDefaultCreationGateRemainsClosedAndWithinClub28Scope() async throws {
        let defaultGate = ClubCreationGate.productionDefault
        XCTAssertFalse(defaultGate.isConfigured)
        XCTAssertEqual(defaultGate.writeAvailability, .unverified)
        XCTAssertEqual(defaultGate.catalogSubviewCount, 28)
        XCTAssertTrue(defaultGate.withinClub28Scope)
        XCTAssertTrue(defaultGate.isBlocked)
        XCTAssertFalse(defaultGate.isCreationAllowed)

        // Expanding beyond the 28-subview Club feature catalog is rejected by the gate.
        let expandedGate = ClubCreationGate(
            isConfigured: true,
            writeAvailability: .approved,
            catalogSubviewCount: 29
        )
        XCTAssertFalse(expandedGate.withinClub28Scope)
        XCTAssertTrue(expandedGate.isBlocked)

        // Unverified fixture adapter refuses creation dispatch and blocks entering management.
        let access = ClubOperationsFixtureAccess(scenario: .unverified)
        let coordinator = ClubOperationsCoordinator(access: access)
        let identity = try XCTUnwrap(access.identity)
        let review = try await coordinator.prepare(
            .create(validCreateDraft()),
            target: .create,
            expectedIdentity: identity,
            ownerID: UUID()
        )
        await coordinator.confirm(review)
        XCTAssertEqual(coordinator.state(target: .create), .notSent)
        XCTAssertEqual(access.writeCount, 0)

        var flow = ClubCreateToManageFlowState(
            gate: ClubCreationGate(access: access),
            receiptAccountId: identity.accountID,
            receiptClubId: 82,
            currentAccountId: identity.accountID,
            readbackAccountId: identity.accountID,
            readbackOwnedClubIds: [81, 82],
            readbackSucceeded: true,
            requestedTab: "manage"
        )
        XCTAssertEqual(flow.blockReason, .gateBlocked)
        XCTAssertFalse(flow.canEnterManagement)
        XCTAssertEqual(flow.validatedTab, .overview)
        XCTAssertNil(flow.enterClubManagement())
        XCTAssertTrue(flow.bilingualStatusCopy.contains("俱乐部创建门控未开启"))
        XCTAssertTrue(flow.bilingualStatusCopy.contains("Club creation gate is closed"))
    }

    func testConfirmedReceiptAndSameAccountReadbackEnablesEnterManagementAndValidatesTab() async throws {
        let access = ClubOperationsFixtureAccess(scenario: .owner)
        let coordinator = ClubOperationsCoordinator(access: access)
        let identity = try XCTUnwrap(access.identity)
        let ownerID = UUID()

        let review = try await coordinator.prepare(
            .create(validCreateDraft()),
            target: .create,
            expectedIdentity: identity,
            ownerID: ownerID
        )
        await coordinator.confirm(review)

        guard case .acknowledged(let receipt) = coordinator.state(target: .create) else {
            XCTFail("Expected confirmed create receipt")
            return
        }
        let createdClubID = try XCTUnwrap(receipt.clubID)
        XCTAssertEqual(createdClubID, 82)

        guard case .received(let readbackSnapshot) = coordinator.readback(target: .create) else {
            XCTFail("Expected same-account readback snapshot")
            return
        }
        XCTAssertTrue(readbackSnapshot.ownedClubIDs.contains(createdClubID))

        var flow = ClubCreateToManageFlowState(
            gate: ClubCreationGate(access: access),
            receiptAccountId: identity.accountID,
            receiptClubId: createdClubID,
            currentAccountId: access.identity?.accountID,
            readbackAccountId: access.identity?.accountID,
            readbackOwnedClubIds: readbackSnapshot.ownedClubIDs,
            readbackSucceeded: true,
            requestedTab: "manage"
        )

        XCTAssertNil(flow.blockReason)
        XCTAssertTrue(flow.canEnterManagement)
        XCTAssertEqual(flow.validatedTab, .manage)
        XCTAssertEqual(ClubCreateToManageFlowState.enterManagementButtonTitle, "进入俱乐部管理 / Enter Club Management")
        XCTAssertTrue(flow.bilingualStatusCopy.contains("同账号回读已确认（俱乐部 #82）"))
        XCTAssertTrue(flow.bilingualStatusCopy.contains("Same-account readback verified (Club #82)"))

        let destination = try XCTUnwrap(flow.enterClubManagement())
        XCTAssertEqual(destination, ClubCreateToManageDestination(accountId: 701, clubId: 82, tab: .manage))
        XCTAssertEqual(flow.enteredDestination, destination)
    }

    func testWorkspaceTabValidationFallsBackSafelyToOverviewWhenNilInvalidOrBlocked() {
        XCTAssertEqual(ClubWorkspaceTab.validate(requestedTab: nil), .overview)
        XCTAssertEqual(ClubWorkspaceTab.validate(requestedTab: ""), .overview)
        XCTAssertEqual(ClubWorkspaceTab.validate(requestedTab: "   "), .overview)
        XCTAssertEqual(ClubWorkspaceTab.validate(requestedTab: "invalid-tab"), .overview)
        XCTAssertEqual(ClubWorkspaceTab.validate(requestedTab: "MANAGE"), .manage)
        XCTAssertEqual(ClubWorkspaceTab.validate(requestedTab: "events"), .events)
        XCTAssertEqual(ClubWorkspaceTab.validate(requestedTab: "posts"), .posts)
        XCTAssertEqual(ClubWorkspaceTab.resolve(requestedTab: "manage", canEnterManagement: false), .overview)
        XCTAssertEqual(ClubWorkspaceTab.resolve(requestedTab: "manage", canEnterManagement: true), .manage)

        var verifiedFlow = ClubCreateToManageFlowState(
            gate: ClubCreationGate(isConfigured: true, writeAvailability: .approved),
            receiptAccountId: 701,
            receiptClubId: 82,
            currentAccountId: 701,
            readbackAccountId: 701,
            readbackOwnedClubIds: [81, 82],
            readbackSucceeded: true,
            requestedTab: "unknown_tab"
        )
        XCTAssertTrue(verifiedFlow.canEnterManagement)
        XCTAssertEqual(verifiedFlow.validatedTab, .overview)
        XCTAssertEqual(
            verifiedFlow.enterClubManagement(requestedTab: nil),
            ClubCreateToManageDestination(accountId: 701, clubId: 82, tab: .overview)
        )
    }

    func testReadbackFailureOrClubIdMismatchBlocksEnteringManagement() async throws {
        let access = ClubOperationsFixtureAccess(scenario: .readbackUnavailable)
        let coordinator = ClubOperationsCoordinator(access: access)
        let identity = try XCTUnwrap(access.identity)
        let review = try await coordinator.prepare(
            .create(validCreateDraft()),
            target: .create,
            expectedIdentity: identity,
            ownerID: UUID()
        )
        await coordinator.confirm(review)

        XCTAssertEqual(coordinator.readback(target: .create), .unavailable)

        var failedReadbackFlow = ClubCreateToManageFlowState(
            gate: ClubCreationGate(access: access),
            receiptAccountId: identity.accountID,
            receiptClubId: 82,
            currentAccountId: identity.accountID,
            readbackAccountId: nil,
            readbackOwnedClubIds: [],
            readbackSucceeded: false,
            requestedTab: "manage"
        )
        XCTAssertEqual(failedReadbackFlow.blockReason, .readbackFailed)
        XCTAssertFalse(failedReadbackFlow.canEnterManagement)
        XCTAssertEqual(failedReadbackFlow.validatedTab, .overview)
        XCTAssertNil(failedReadbackFlow.enterClubManagement())
        XCTAssertTrue(failedReadbackFlow.bilingualStatusCopy.contains("同账号回读校验未通过"))
        XCTAssertTrue(failedReadbackFlow.bilingualStatusCopy.contains("Same-account readback verification failed"))

        var mismatchedClubFlow = ClubCreateToManageFlowState(
            gate: ClubCreationGate(isConfigured: true, writeAvailability: .approved),
            receiptAccountId: 701,
            receiptClubId: 82,
            currentAccountId: 701,
            readbackAccountId: 701,
            readbackOwnedClubIds: [81],
            readbackSucceeded: true,
            requestedTab: "manage"
        )
        XCTAssertEqual(mismatchedClubFlow.blockReason, .clubIdMismatch)
        XCTAssertFalse(mismatchedClubFlow.canEnterManagement)
        XCTAssertNil(mismatchedClubFlow.enterClubManagement())
        XCTAssertTrue(mismatchedClubFlow.bilingualStatusCopy.contains("俱乐部 ID 回读不匹配"))
        XCTAssertTrue(mismatchedClubFlow.bilingualStatusCopy.contains("Club ID readback mismatch"))
    }

    func testAccountMismatchBlocksEnteringManagementEvenAfterReceipt() {
        var switchedAccountFlow = ClubCreateToManageFlowState(
            gate: ClubCreationGate(isConfigured: true, writeAvailability: .approved),
            receiptAccountId: 701,
            receiptClubId: 82,
            currentAccountId: 702,
            readbackAccountId: 701,
            readbackOwnedClubIds: [81, 82],
            readbackSucceeded: true,
            requestedTab: "manage"
        )
        XCTAssertEqual(switchedAccountFlow.blockReason, .accountMismatch)
        XCTAssertFalse(switchedAccountFlow.canEnterManagement)
        XCTAssertEqual(switchedAccountFlow.validatedTab, .overview)
        XCTAssertNil(switchedAccountFlow.enterClubManagement())
        XCTAssertTrue(switchedAccountFlow.bilingualStatusCopy.contains("账号已变更或不匹配"))
        XCTAssertTrue(switchedAccountFlow.bilingualStatusCopy.contains("Account mismatch detected"))

        var foreignReadbackFlow = ClubCreateToManageFlowState(
            gate: ClubCreationGate(isConfigured: true, writeAvailability: .approved),
            receiptAccountId: 701,
            receiptClubId: 82,
            currentAccountId: 701,
            readbackAccountId: 702,
            readbackOwnedClubIds: [81, 82],
            readbackSucceeded: true,
            requestedTab: "manage"
        )
        XCTAssertEqual(foreignReadbackFlow.blockReason, .accountMismatch)
        XCTAssertFalse(foreignReadbackFlow.canEnterManagement)
        XCTAssertNil(foreignReadbackFlow.enterClubManagement())
    }
}
