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
            private(set) var queriedAftercarePages: [MerchantBusinessQuery] = []
            func access() async throws -> MerchantBusinessAccess {
                try .init(["active": .bool(true), "merchant": .object(["id": .int(31), "name": .string("Store")]),
                           "roleCode": .string("MERCHANT_MANAGER"),
                           "permissions": .array([.string("merchant:basic:read"), .string("merchant:aftercare:read")])])
            }
            func snapshot(_ query: MerchantBusinessQuery) async throws -> MerchantBusinessSnapshot {
                queriedAftercarePages.append(query)
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
        XCTAssertEqual(MerchantWorkbenchReminders.aftercareCount(model.value, access: granted, isLoading: false), 1)
        XCTAssertEqual(businessReader.queriedAftercarePages.count, 2)
        XCTAssertTrue(wire.requests.isEmpty)
    }
}
