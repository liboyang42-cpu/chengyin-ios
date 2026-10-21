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
    func testOverviewReaderAllowsAftercareScopedTodoWithoutOpeningDashboardOrEvents() async throws {
        final class OverviewTransport: HTTPTransport {
            var requests: [URLRequest] = []
            func send(_ request: URLRequest) async throws -> (Data, Int) {
                requests.append(request)
                switch request.url?.lastPathComponent {
                case "me":
                    return (Data(#"{"code":200,"data":{"active":true,"merchant":{"id":31,"name":"Store"},"roleCode":"MERCHANT_MANAGER","permissions":["merchant:basic:read","merchant:aftercare:read","merchant:project:manage"]}}"#.utf8), 200)
                case "todo-summary":
                    return (Data(#"{"code":200,"data":{"pendingVerify":2,"verifiedCount":8,"pendingScanConfirm":3,"pendingOrders":4,"refundCount":5,"pendingPredict":6,"biddingTopics":7,"byProject":[{"ownerType":"topic","ownerId":"01","pendingVerify":1,"pendingScanConfirm":2}]}}"#.utf8), 200)
                default:
                    return (Data(#"{"code":200,"data":{}}"#.utf8), 200)
                }
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
        XCTAssertTrue(wire.requests.isEmpty)
        let scoped = try await reader.merchantTodo(access: granted)
        XCTAssertEqual(wire.requests.map { $0.url?.lastPathComponent }, ["todo-summary"])
        XCTAssertEqual(scoped.refundCount, 5)
        XCTAssertEqual(scoped.pendingVerify, 0)
        XCTAssertEqual(scoped.verifiedCount, 0)
        XCTAssertEqual(scoped.pendingScanConfirm, 0)
        XCTAssertEqual(scoped.pendingOrders, 0)
        XCTAssertEqual(scoped.pendingPredict, 0)
        XCTAssertEqual(scoped.biddingTopics, 0)
        XCTAssertNil(scoped.byProject)
        XCTAssertEqual(MerchantWorkbenchReminders.aftercareCount(scoped, access: granted, isLoading: false), 5)
        XCTAssertNil(MerchantWorkbenchReminders.predictCount(scoped, access: granted, isLoading: false))
    }
}
