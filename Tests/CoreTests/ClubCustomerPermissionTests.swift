import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private func directoryAccess(roles: [String] = [], permissions: [String] = [], clubID: Int = 81,
                             active: Bool = true, events: [ClubGovernanceValue] = []) -> ClubGovernanceValue {
    .object(["active": .bool(active), "club": .object(["id": .integer(clubID)]),
             "roleCodes": .array(roles.map(ClubGovernanceValue.string)),
             "permissions": .array(permissions.map(ClubGovernanceValue.string)), "eventAccesses": .array(events)])
}
private let directoryEvent: ClubGovernanceValue = .object([
    "activityId": .integer(101), "topicId": .integer(91), "roleCodes": .array([.string("EVENT_LEAD")]),
    "permissions": .array([.string("club:member:manage"), .string("club:member:list:read"), .string("club:event:checkin")])])

/// Authored native tests; execute with the approved Apple/Swift toolchain.
@MainActor final class ClubCustomerPermissionTests: XCTestCase {
    private let operations: [ClubGovernanceRead] = [.customers, .customer, .customerCount]
    private let scope = ClubGovernanceScope(clubID: 81, topicID: 91, activityID: 101, memberID: 704)
    private func permission(_ raw: ClubGovernanceValue) throws -> ClubGovernancePermissions {
        try .init(value: raw, scope: .init(clubID: raw["club"]["id"].int))
    }
    func testExactGovernorMatrixForAllCustomerDirectoryReads() throws {
        let allowed = [directoryAccess(roles: ["CLUB_OWNER"]), directoryAccess(roles: ["CLUB_LEGACY_ADMIN"]),
                       directoryAccess(permissions: ["club:member:manage"]),
                       directoryAccess(roles: ["CLUB_CO_OWNER"], permissions: ["club:member:manage"])]
        let denied = [directoryAccess(), directoryAccess(roles: ["CLUB_OPERATOR"], permissions: ["club:member:list:read"]),
                      directoryAccess(roles: ["CLUB_CO_OWNER"]), directoryAccess(roles: ["EVENT_LEAD", "EVENT_CHECKIN"]),
                      directoryAccess(permissions: ["club:finance:read", "club:event:checkin", "CUSTOMER_DIRECTORY"]),
                      directoryAccess(events: [directoryEvent]),
                      directoryAccess(events: [.object(["activityId": .integer(101), "topicId": .integer(91),
                          "roleCodes": .array([.string("EVENT_CHECKIN")]), "permissions": .array([.string("CUSTOMER_DIRECTORY")])])]),
                      directoryAccess(roles: ["CLUB_OWNER"], clubID: 82)]
        for operation in operations {
            XCTAssertEqual(operation.permission, "CUSTOMER_DIRECTORY")
            for raw in allowed { XCTAssertTrue(try permission(raw).allows(operation.permission, scope: scope)) }
            for raw in denied { XCTAssertFalse(try permission(raw).allows(operation.permission, scope: scope)) }
        }
        XCTAssertThrowsError(try permission(directoryAccess(roles: ["CLUB_OWNER"], active: false)))
    }
    func testInvalidScopeAndLegacyFlagsCannotAuthorizeDirectory() throws {
        let owner = try permission(directoryAccess(roles: ["CLUB_OWNER"]))
        for target in [ClubGovernanceScope(), .init(clubID: 0), .init(clubID: 82),
                       .init(clubID: 81, activityID: -1), .init(clubID: 81, memberID: 0),
                       .init(clubID: 81, topicID: 0), .init(clubID: 81, registrationID: 0),
                       .init(clubID: 81, campaignID: -1)] {
            XCTAssertFalse(owner.allows(ClubGovernanceRead.customers.permission, scope: target))
        }
        var legacy = directoryAccess().object!
        legacy["isOwner"] = .bool(true); legacy["viewerIsAdmin"] = .bool(true)
        XCTAssertFalse(try permission(.object(legacy)).allows(ClubGovernanceRead.customers.permission, scope: scope))
    }
    func testDeniedPreflightOnlyRequestsAccessForEachDirectoryEndpoint() async throws {
        for operation in operations {
            for raw in [directoryAccess(permissions: ["club:member:list:read"]), directoryAccess(events: [directoryEvent]),
                        directoryAccess(permissions: ["CUSTOMER_DIRECTORY"]), directoryAccess(active: false)] {
                let wire = Wire(access: raw)
                do { _ = try await read(operation, wire: wire); XCTFail("Denied directory request escaped") }
                catch { XCTAssertEqual(error as? ClubGovernanceFailure, .forbidden) }
                XCTAssertEqual(wire.requests.map { $0.url!.path }, ["/api/club/access/me"])
            }
        }
    }
    func testAllowedDirectoryReadsKeepExactPayloadAndServerRedaction() async throws {
        for operation in operations {
            let wire = Wire(access: directoryAccess(permissions: ["club:member:manage"]))
            let snapshot = try await read(operation, wire: wire)
            XCTAssertEqual(wire.requests.map { $0.url!.path }, ["/api/club/access/me", "/" + operation.path])
            let payload = try JSONDecoder().decode(ClubGovernanceValue.self, from: XCTUnwrap(wire.requests.last?.httpBody))
            XCTAssertEqual(payload, .object(try operation.fields(scope: scope, options: options(operation))))
            let expected: [String: ClubGovernanceValue]
            switch operation {
            case .customers: expected = ["clubId": .integer(81), "filter": .string("remark"), "keyword": .string(" 顾客 ")]
            case .customer: expected = ["clubId": .integer(81), "memberId": .integer(704)]
            case .customerCount: expected = ["clubId": .integer(81)]
            default: XCTFail("Unexpected directory operation"); return
            }
            XCTAssertEqual(payload, .object(expected))
            XCTAssertEqual(snapshot.value, ClubGovernanceFixtures.value(operation))
            if operation == .customers { XCTAssertEqual(snapshot.value["items"].array?.first?["phoneText"], .string("Hidden")) }
            if operation == .customer { XCTAssertEqual(snapshot.value["summary"]["phoneText"], .string("Hidden")) }
        }
    }
    func testServerDenialRemainsFinalForEveryAllowedDirectoryEndpoint() async throws {
        for operation in operations {
            let wire = Wire(access: directoryAccess(roles: ["CLUB_OWNER"])); wire.denyData = true
            do { _ = try await read(operation, wire: wire); XCTFail("Server denial was ignored") }
            catch { XCTAssertEqual(error as? ClubGovernanceFailure, .forbidden) }
            XCTAssertEqual(wire.requests.count, 2)
        }
    }
    func testBothReadStagesRetainCancellationChecks() async throws {
        for operation in operations {
            for retireAfter in [1, 2] {
                let wire = Wire(access: directoryAccess(roles: ["CLUB_OWNER"]))
                do {
                    _ = try await read(operation, wire: wire) {
                        if wire.requests.count >= retireAfter { throw CancellationError() }
                    }
                    XCTFail("Cancelled customer response escaped")
                } catch { XCTAssertTrue(error is CancellationError) }
                XCTAssertEqual(wire.requests.count, retireAfter)
            }
        }
    }
    func testReceiptEnrollmentAndContactVisibilityRemainIndependent() throws {
        let contact = try permission(directoryAccess(permissions: ["club:member:list:read"]))
        XCTAssertTrue(contact.allows(ClubGovernanceRead.registrations.permission, scope: scope))
        XCTAssertFalse(contact.allows(ClubGovernanceRead.customers.permission, scope: scope))
        let checkin = try permission(directoryAccess(permissions: ["club:event:checkin"]))
        XCTAssertEqual(ClubGovernanceRead.checkin.permission, "club:member:list:read")
        XCTAssertFalse(checkin.allows(ClubGovernanceRead.checkin.permission, scope: .init(clubID: 81, registrationID: 121)))
        XCTAssertTrue(contact.allows(ClubGovernanceRead.checkin.permission, scope: .init(clubID: 81, registrationID: 121)))
        XCTAssertFalse(checkin.allows(ClubGovernanceRead.customers.permission, scope: scope))
        let governor = try permission(directoryAccess(permissions: ["club:member:manage"]))
        XCTAssertTrue(governor.allows(ClubGovernanceRead.customers.permission, scope: scope))
        XCTAssertFalse(governor.allows("club:member:list:read", scope: scope))
        for role in ["CLUB_OWNER", "CLUB_LEGACY_ADMIN"] {
            let owner = try permission(directoryAccess(roles: [role]))
            XCTAssertTrue(owner.allows(ClubGovernanceRead.customers.permission, scope: scope))
            XCTAssertFalse(owner.allows("club:member:list:read", scope: scope))
            XCTAssertFalse(owner.allows(ClubGovernanceRead.checkin.permission, scope: .init(clubID: 81, registrationID: 121)))
        }
    }
    private func options(_ operation: ClubGovernanceRead) -> [String: ClubGovernanceValue] {
        operation == .customers ? ["filter": .string("remark"), "keyword": .string(" 顾客 ")] : [:]
    }
    private func read(_ operation: ClubGovernanceRead, wire: Wire, check: () throws -> Void = {}) async throws -> ClubGovernanceSnapshot {
        let service = ClubGovernanceService(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: wire)
        return try await service.read(operation, scope: scope, options: options(operation),
            session: .init(accountID: 701, epoch: 1, token: "synthetic"), check: check)
    }
    private final class Wire: HTTPTransport {
        let access: ClubGovernanceValue
        var requests: [URLRequest] = []
        var denyData = false
        init(access: ClubGovernanceValue) { self.access = access }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            let operation = try XCTUnwrap(ClubGovernanceRead.allCases.first { "/" + $0.path == request.url?.path })
            let value = operation == .access ? access : ClubGovernanceFixtures.value(operation)
            return (try JSONEncoder().encode(ClubGovernanceValue.object([
                "code": .integer(operation != .access && denyData ? 403 : 200), "data": value])), 200)
        }
    }
}
