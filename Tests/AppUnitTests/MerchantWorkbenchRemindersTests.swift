import XCTest
@testable import Questify

/// Mini-program index.wxml:113-132: aftercare needs canReadAftercare, prediction needs
/// canManageProjects, both need a loaded positive count and never show while loading.
@MainActor final class MerchantWorkbenchRemindersTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }
    private func access(_ permissions: [String], role: String = "MERCHANT_OWNER") throws -> MerchantAccess {
        let names = permissions.map { "\"\($0)\"" }.joined(separator: ",")
        return try decode(MerchantAccess.self, #"{"active":true,"merchant":{"id":31},"roleCode":""# + role + #"","permissions":["# + names + "]}")
    }
    func testRemindersFollowMiniProgramPermissionGates() throws {
        let todo = try decode(MerchantTodo.self, #"{"refundCount":2,"pendingPredict":3}"#)
        let both = try access(["merchant:aftercare:read", "merchant:project:manage"], role: "MERCHANT_MANAGER")
        XCTAssertFalse(both.isOwner)
        XCTAssertTrue(both.canReadAftercare)
        XCTAssertEqual(MerchantWorkbenchReminders.aftercareCount(todo, access: both, isLoading: false), 2)
        XCTAssertEqual(MerchantWorkbenchReminders.predictCount(todo, access: both, isLoading: false), 3)
        let ownerWithoutAftercare = try access(["merchant:finance:read"], role: "MERCHANT_OWNER")
        XCTAssertTrue(ownerWithoutAftercare.isOwner)
        XCTAssertFalse(ownerWithoutAftercare.canReadAftercare)
        XCTAssertNil(MerchantWorkbenchReminders.aftercareCount(todo, access: ownerWithoutAftercare, isLoading: false))
        XCTAssertNil(MerchantWorkbenchReminders.predictCount(todo, access: ownerWithoutAftercare, isLoading: false))
    }
    func testRemindersHideWhileLoadingUnknownOrZero() throws {
        let both = try access(["merchant:aftercare:read", "merchant:project:manage"])
        let todo = try decode(MerchantTodo.self, #"{"refundCount":2,"pendingPredict":3}"#)
        XCTAssertNil(MerchantWorkbenchReminders.aftercareCount(todo, access: both, isLoading: true))
        XCTAssertNil(MerchantWorkbenchReminders.predictCount(nil, access: both, isLoading: false))
        let zero = try decode(MerchantTodo.self, #"{"refundCount":0,"pendingPredict":0}"#)
        XCTAssertNil(MerchantWorkbenchReminders.aftercareCount(zero, access: both, isLoading: false))
        XCTAssertNil(MerchantWorkbenchReminders.predictCount(zero, access: both, isLoading: false))
    }
    func testAftercareStaffUsesApprovedAftercareSourceAndRefreshesOnReturnWithoutOwnerTodoSummary() async throws {
        final class OverviewTransport: HTTPTransport {
            var requests: [URLRequest] = []
            func send(_ request: URLRequest) async throws -> (Data, Int) {
                requests.append(request)
                switch request.url?.lastPathComponent {
                case "me":
                    return (Data(#"{"code":200,"data":{"active":true,"merchant":{"id":31,"name":"Store"},"roleCode":"MERCHANT_MANAGER","permissions":["merchant:basic:read","merchant:aftercare:read","merchant:project:manage"]}}"#.utf8), 200)
                case "todo-summary":
                    XCTFail("Non-owner aftercare staff must never request owner todo-summary")
                    return (Data(#"{"code":403}"#.utf8), 403)
                default:
                    return (Data(#"{"code":200,"data":{}}"#.utf8), 200)
                }
            }
        }
        @MainActor final class NarrowAftercareBusinessReader: MerchantBusinessReading {
            var scope: MerchantBusinessScope? = .init(realm: "fixture://merchant", accountID: 9001, epoch: 1)
            var authorizationGeneration: UUID? = UUID()
            var isConfigured = true, isOfflineExample = false, canExecuteSyntheticMutation = false
            var pendingTotal = 3
            var forcedFailure: MerchantBusinessFailure?
            var permissions: [MerchantBusinessValue] = [.string("merchant:basic:read"), .string("merchant:aftercare:read")]
            private(set) var queriedAftercarePages: [MerchantBusinessQuery] = []
            func access() async throws -> MerchantBusinessAccess {
                if let forcedFailure {
                    throw forcedFailure
                }
                return try .init(["active": .bool(true), "merchant": .object(["id": .int(31), "name": .string("Store")]),
                           "roleCode": .string("MERCHANT_MANAGER"),
                           "permissions": .array(permissions)])
            }
            func snapshot(_ query: MerchantBusinessQuery) async throws -> MerchantBusinessSnapshot {
                queriedAftercarePages.append(query)
                if let forcedFailure {
                    throw forcedFailure
                }
                let items: [MerchantBusinessValue] = (0..<pendingTotal).map { index in
                    .object([
                        "refundId": .int(62001 + index),
                        "refundNo": .string("RF-\(62001 + index)"),
                        "processing": .string("WAITING_PLATFORM_REVIEW"),
                        "merchantOpinion": .string("PENDING"),
                        "refundAmount": .string("19.90"),
                        "canRespond": .bool(true),
                        "bucket": .string("PENDING"),
                        "refunded": .bool(false)
                    ])
                }
                let payload: MerchantBusinessValue = .object([
                    "bucket": .string("PENDING"),
                    "pageNum": .int(query.page), "pageSize": .int(20),
                    "total": .int(pendingTotal), "hasMore": .bool(false), "items": .array(items)
                ])
                return .init(access: try await access(), document: try .init(query: query, payload: payload))
            }
            func execute(_ mutation: MerchantBusinessMutation, requestID: String, scope: MerchantBusinessScope) async throws -> MerchantBusinessReceipt {
                throw URLError(.timedOut)
            }
        }
        let wire = OverviewTransport()
        let config = try APIConfiguration(baseURL: URL(string: "https://overview.example/native")!)
        let reader = MerchantOverviewReader(configuration: config, transport: wire, token: "fixture-token", revision: 1, current: { true }, unauthorized: {})
        let granted = try await reader.merchantAccess()
        XCTAssertFalse(granted.isOwner)
        XCTAssertTrue(granted.canReadAftercare)
        wire.requests = []
        do { _ = try await reader.merchantDashboard(access: granted); XCTFail() } catch { XCTAssertEqual(error as? MerchantReadError, .accessDenied) }
        do { _ = try await reader.merchantEvents(access: granted); XCTFail() } catch { XCTAssertEqual(error as? MerchantReadError, .accessDenied) }
        do { _ = try await reader.merchantTodo(access: granted); XCTFail() } catch { XCTAssertEqual(error as? MerchantReadError, .accessDenied) }
        XCTAssertTrue(wire.requests.isEmpty)

        // 1. When businessReader is unavailable (nil), todo stays unavailable and never falls back to owner todo-summary.
        let model = MerchantLoadModel<MerchantTodo>()
        await MerchantWorkbenchTodoLoader.load(into: model, reader: reader, access: granted, businessReader: nil)
        XCTAssertNil(model.value)
        XCTAssertEqual(model.errorKey, "auth.notConfigured")
        XCTAssertTrue(wire.requests.isEmpty)

        // 2. When approved businessReader is present, loadTodo reads narrow aftercare(.pending, page: 1) and refreshes on return.
        let businessReader = NarrowAftercareBusinessReader()
        let journal = MerchantBusinessMemoryIntentStore()
        await MerchantWorkbenchTodoLoader.load(into: model, reader: reader, access: granted, businessReader: businessReader)
        XCTAssertNil(model.errorKey)
        XCTAssertEqual(model.value?.refundCount, 3)
        XCTAssertEqual(model.value?.pendingVerify, 0)
        XCTAssertEqual(model.value?.pendingOrders, 0)
        XCTAssertEqual(MerchantWorkbenchReminders.aftercareCount(model.value, access: granted, isLoading: false), 3)
        XCTAssertEqual(businessReader.queriedAftercarePages, [.aftercare(.pending, page: 1)])
        XCTAssertTrue(wire.requests.isEmpty)

        // Route into aftercare list/detail is current and valid for the staff member:
        let route = try XCTUnwrap(MerchantWorkbenchBusinessRoute(shortcut: .aftercare, reader: businessReader, journal: journal))
        XCTAssertTrue(route.isCurrent(reader: businessReader, journal: journal))
        XCTAssertEqual(route.shortcut.query, .aftercare(.pending, page: 1))

        // Simulate returning from aftercare list/detail after pending count drops to 1:
        businessReader.pendingTotal = 1
        await MerchantWorkbenchTodoLoader.load(into: model, reader: reader, access: granted, businessReader: businessReader)
        XCTAssertEqual(model.value?.refundCount, 1)
        XCTAssertEqual(MerchantWorkbenchReminders.aftercareCount(model.value, access: granted, isLoading: false, errorKey: model.errorKey), 1)
        XCTAssertEqual(businessReader.queriedAftercarePages.count, 2)
        XCTAssertTrue(wire.requests.isEmpty)

        // 3. Same-session revocation or stale scope during return refresh clears model.value and hides reminder:
        businessReader.forcedFailure = .denied
        await MerchantWorkbenchTodoLoader.load(into: model, reader: reader, access: granted, businessReader: businessReader)
        XCTAssertNil(model.value)
        XCTAssertEqual(model.errorKey, "merchant.access.denied")
        XCTAssertNil(MerchantWorkbenchReminders.aftercareCount(model.value, access: granted, isLoading: model.isLoading, errorKey: model.errorKey))
        XCTAssertTrue(wire.requests.isEmpty)

        // Restore valid narrow read, then revoke merchant:aftercare:read permission inside snapshot.access:
        businessReader.forcedFailure = nil
        businessReader.pendingTotal = 2
        await MerchantWorkbenchTodoLoader.load(into: model, reader: reader, access: granted, businessReader: businessReader)
        XCTAssertEqual(model.value?.refundCount, 2)
        XCTAssertEqual(MerchantWorkbenchReminders.aftercareCount(model.value, access: granted, isLoading: model.isLoading, errorKey: model.errorKey), 2)

        businessReader.permissions = [.string("merchant:basic:read")]
        await MerchantWorkbenchTodoLoader.load(into: model, reader: reader, access: granted, businessReader: businessReader)
        XCTAssertNil(model.value)
        XCTAssertEqual(model.errorKey, "merchant.access.denied")
        XCTAssertNil(MerchantWorkbenchReminders.aftercareCount(model.value, access: granted, isLoading: model.isLoading, errorKey: model.errorKey))
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testMerchantRootModeSwitchVerifiesAccessNavigatesFiveTabsAndCleansUpOnReturn() async throws {
        @MainActor final class StubMerchantReader: MerchantReading {
            var isConfigured = true
            var isSignedIn = true
            var sessionRevision: UInt64 = 10
            var result: Result<MerchantAccess, Error>
            var onAccessRequested: (() async -> Void)?
            init(result: Result<MerchantAccess, Error>) { self.result = result }
            func merchantAccess() async throws -> MerchantAccess {
                await onAccessRequested?()
                return try result.get()
            }
            func merchantDashboard(access: MerchantAccess) async throws -> MerchantDashboard { throw MerchantReadError.accessDenied }
            func merchantTodo(access: MerchantAccess) async throws -> MerchantTodo { throw MerchantReadError.accessDenied }
            func merchantEvents(access: MerchantAccess) async throws -> [MerchantEvent] { throw MerchantReadError.accessDenied }
            func merchantOrders(access: MerchantAccess, filter: MerchantOrderFilter) async throws -> [MerchantOrder] { throw MerchantReadError.accessDenied }
            func merchantProjects(access: MerchantAccess) async throws -> MerchantProjectPage { throw MerchantReadError.accessDenied }
        }
        let coordinator = MerchantRootModeCoordinator()
        let initialGeneration = coordinator.merchantContainerGeneration

        // 1. Denied / inactive merchant access refuses to enter merchant root mode:
        let inactiveAccess = try decode(MerchantAccess.self, #"{"active":false,"merchant":{"id":31},"roleCode":"MERCHANT_OWNER","permissions":[]}"#)
        let deniedReader = StubMerchantReader(result: .success(inactiveAccess))
        let denied = await coordinator.requestMerchantMode(reader: deniedReader, accountID: 501)
        XCTAssertFalse(denied)
        XCTAssertEqual(coordinator.requestedMode, .consumer)
        XCTAssertFalse(coordinator.isMerchantModeActive(accountID: 501, isSignedIn: true, isConfigured: true, revision: 10))
        XCTAssertEqual(coordinator.statusErrorKey, "merchant.access.inactive")

        // 2. Active merchant access enters Merchant Root Mode and unlocks the 5 business tabs according to permissions:
        let managerAccess = try access(["merchant:basic:read", "merchant:project:manage", "merchant:coop:manage"], role: "MERCHANT_MANAGER")
        let clerkAccess = try access(["merchant:aftercare:read"], role: "MERCHANT_FINANCE")
        let activeReader = StubMerchantReader(result: .success(managerAccess))
        let entered = await coordinator.requestMerchantMode(reader: activeReader, accountID: 501)
        XCTAssertTrue(entered)
        XCTAssertEqual(coordinator.requestedMode, .merchant)
        XCTAssertTrue(coordinator.isMerchantModeActive(accountID: 501, isSignedIn: true, isConfigured: true, revision: 10))
        XCTAssertNil(coordinator.statusErrorKey)
        XCTAssertNotEqual(coordinator.merchantContainerGeneration, initialGeneration)
        let enteredGeneration = coordinator.merchantContainerGeneration

        XCTAssertEqual(MerchantRootBusinessTab.allCases.map(\.rootTab), [.home, .roam, .publish, .club, .mine])
        XCTAssertTrue(MerchantRootModeCoordinator.allowsBusinessTab(.workbench, access: managerAccess))
        XCTAssertTrue(MerchantRootModeCoordinator.allowsBusinessTab(.marketing, access: managerAccess))
        XCTAssertTrue(MerchantRootModeCoordinator.allowsBusinessTab(.templates, access: managerAccess))
        XCTAssertTrue(MerchantRootModeCoordinator.allowsBusinessTab(.cooperation, access: managerAccess))
        XCTAssertTrue(MerchantRootModeCoordinator.allowsBusinessTab(.mine, access: managerAccess))

        XCTAssertTrue(MerchantRootModeCoordinator.allowsBusinessTab(.workbench, access: clerkAccess))
        XCTAssertFalse(MerchantRootModeCoordinator.allowsBusinessTab(.marketing, access: clerkAccess))
        XCTAssertFalse(MerchantRootModeCoordinator.allowsBusinessTab(.templates, access: clerkAccess))
        XCTAssertFalse(MerchantRootModeCoordinator.allowsBusinessTab(.cooperation, access: clerkAccess))
        XCTAssertTrue(MerchantRootModeCoordinator.allowsBusinessTab(.mine, access: clerkAccess))

        for tab in MerchantRootBusinessTab.allCases {
            coordinator.selectBusinessTab(tab)
            XCTAssertEqual(coordinator.selectedMerchantTab, tab)
        }

        // 3. Switching back to player mode resets tab, clears merchant grant, and rotates container generation:
        coordinator.switchToConsumerMode()
        XCTAssertEqual(coordinator.requestedMode, .consumer)
        XCTAssertNil(coordinator.verifiedAccess)
        XCTAssertEqual(coordinator.selectedMerchantTab, .workbench)
        XCTAssertFalse(coordinator.isMerchantModeActive(accountID: 501, isSignedIn: true, isConfigured: true, revision: 10))
        XCTAssertNotEqual(coordinator.merchantContainerGeneration, enteredGeneration)

        // 4. Re-enter and verify account/revision change immediately tears down merchant mode:
        let reentered = await coordinator.requestMerchantMode(reader: activeReader, accountID: 501)
        XCTAssertTrue(reentered)
        coordinator.selectBusinessTab(.cooperation)
        coordinator.handleSessionChange(accountID: 502, isSignedIn: true, isConfigured: true, revision: 10)
        XCTAssertEqual(coordinator.requestedMode, .consumer)
        XCTAssertNil(coordinator.verifiedAccess)
        XCTAssertEqual(coordinator.selectedMerchantTab, .workbench)

        // 5. Same-account, same-sessionRevision permission downgrade (MERCHANT_MANAGER -> MERCHANT_FINANCE):
        activeReader.result = .success(managerAccess)
        let enteredManager = await coordinator.requestMerchantMode(reader: activeReader, accountID: 501)
        XCTAssertTrue(enteredManager)
        coordinator.selectBusinessTab(.cooperation)
        let beforeDowngradeGeneration = coordinator.merchantContainerGeneration
        let downgradeToken = try XCTUnwrap(coordinator.beginAccessObservation(accountID: 501, revision: 10))
        coordinator.applyObservedMerchantAccess(token: downgradeToken, access: clerkAccess, errorKey: nil, currentAccountID: 501, currentRevision: 10)
        XCTAssertEqual(coordinator.requestedMode, .merchant)
        XCTAssertEqual(coordinator.verifiedAccess, clerkAccess)
        XCTAssertEqual(coordinator.selectedMerchantTab, .workbench)
        XCTAssertNotEqual(coordinator.merchantContainerGeneration, beforeDowngradeGeneration)
        let downgradedAccess = try XCTUnwrap(coordinator.verifiedAccess)
        XCTAssertFalse(MerchantRootModeCoordinator.allowsBusinessTab(.cooperation, access: downgradedAccess))

        // 6. Same-account, same-sessionRevision transition active -> inactive tears down merchant mode immediately:
        let beforeRevokeGeneration = coordinator.merchantContainerGeneration
        let revokeToken = try XCTUnwrap(coordinator.beginAccessObservation(accountID: 501, revision: 10))
        coordinator.applyObservedMerchantAccess(token: revokeToken, access: inactiveAccess, errorKey: nil, currentAccountID: 501, currentRevision: 10)
        XCTAssertEqual(coordinator.requestedMode, .consumer)
        XCTAssertNil(coordinator.verifiedAccess)
        XCTAssertEqual(coordinator.selectedMerchantTab, .workbench)
        XCTAssertEqual(coordinator.statusErrorKey, "merchant.access.inactive")
        XCTAssertFalse(coordinator.isMerchantModeActive(accountID: 501, isSignedIn: true, isConfigured: true, revision: 10))
        XCTAssertNotEqual(coordinator.merchantContainerGeneration, beforeRevokeGeneration)

        // 7. Out-of-order observer counter-example:
        // Observer 1 begins while active -> Observer 2 begins and completes with inactive/denied (clearing merchant mode)
        // -> Observer 1 arrives late with old active access -> must be rejected and NEVER resurrect merchant mode:
        activeReader.result = .success(managerAccess)
        let enteredForObserverRace = await coordinator.requestMerchantMode(reader: activeReader, accountID: 501)
        XCTAssertTrue(enteredForObserverRace)
        let earlierObserverToken = try XCTUnwrap(coordinator.beginAccessObservation(accountID: 501, revision: 10))
        let newerObserverToken = try XCTUnwrap(coordinator.beginAccessObservation(accountID: 501, revision: 10))
        coordinator.applyObservedMerchantAccess(
            token: newerObserverToken,
            access: nil,
            errorKey: "merchant.access.denied",
            currentAccountID: 501,
            currentRevision: 10
        )
        XCTAssertEqual(coordinator.requestedMode, .consumer)
        XCTAssertNil(coordinator.verifiedAccess)
        XCTAssertEqual(coordinator.statusErrorKey, "merchant.access.denied")

        // Now the earlier observer completes late with active managerAccess; it must NOT restore merchant mode:
        coordinator.applyObservedMerchantAccess(
            token: earlierObserverToken,
            access: managerAccess,
            errorKey: nil,
            currentAccountID: 501,
            currentRevision: 10
        )
        XCTAssertEqual(coordinator.requestedMode, .consumer)
        XCTAssertNil(coordinator.verifiedAccess)
        XCTAssertFalse(coordinator.isMerchantModeActive(accountID: 501, isSignedIn: true, isConfigured: true, revision: 10))

        // 8. Switch-to-consumer late observer counter-example:
        // Observer begins while active -> user switches to consumer mode -> observer arrives late with active access -> rejected:
        let enteredBeforeSwitch = await coordinator.requestMerchantMode(reader: activeReader, accountID: 501)
        XCTAssertTrue(enteredBeforeSwitch)
        let tokenBeforeConsumerSwitch = try XCTUnwrap(coordinator.beginAccessObservation(accountID: 501, revision: 10))
        coordinator.switchToConsumerMode()
        XCTAssertEqual(coordinator.requestedMode, .consumer)
        XCTAssertNil(coordinator.beginAccessObservation(accountID: 501, revision: 10))
        coordinator.applyObservedMerchantAccess(
            token: tokenBeforeConsumerSwitch,
            access: managerAccess,
            errorKey: nil,
            currentAccountID: 501,
            currentRevision: 10
        )
        XCTAssertEqual(coordinator.requestedMode, .consumer)
        XCTAssertNil(coordinator.verifiedAccess)
        XCTAssertFalse(coordinator.isMerchantModeActive(accountID: 501, isSignedIn: true, isConfigured: true, revision: 10))
    }
}
