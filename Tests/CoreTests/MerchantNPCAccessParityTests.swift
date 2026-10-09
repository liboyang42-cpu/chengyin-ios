import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class NPCAccessParityTransport: HTTPTransport {
    var replies: [String] = []
    var requests: [URLRequest] = []
    var onSend: ((Int) -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        onSend?(requests.count)
        guard !replies.isEmpty else { throw APIError.malformedResponse }
        return (Data(replies.removeFirst().utf8), 200)
    }
}

@MainActor private final class NPCAccessParityJournal: OperationPendingJournal {
    var record: OperationPendingRecord?
    var writes = 0
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { record }
    func write(_ record: OperationPendingRecord) throws { self.record = record; writes += 1 }
    func clear(_ record: OperationPendingRecord) throws { self.record = nil }
}

@MainActor final class MerchantNPCAccessParityTests: XCTestCase {
    private let baseURL = URL(string: "https://example.test/contract")!
    private let profile = #"{"code":200,"data":{"name":"Guide","avatar":"px1:p01","greeting":"Welcome","persona":"Guide","knowledge":"Menu"}}"#
    private func accessJSON(_ permissions: [String], active: Bool = true, role: String = "MERCHANT_OWNER") throws -> String {
        let data = try JSONSerialization.data(withJSONObject: ["active": active, "merchant": ["id": 31], "roleCode": role, "permissions": permissions])
        return String(decoding: data, as: UTF8.self)
    }
    private func access(_ permissions: [String], active: Bool = true, role: String = "MERCHANT_OWNER") throws -> MerchantOperationsAccess {
        try JSONDecoder().decode(MerchantOperationsAccess.self, from: Data(accessJSON(permissions, active: active, role: role).utf8))
    }
    private func envelope(_ permissions: [String]) throws -> String { "{\"code\":200,\"data\":\(try accessJSON(permissions))}" }
    private func service(_ transport: NPCAccessParityTransport) throws -> MerchantOperationsService {
        MerchantOperationsService(configuration: try .init(baseURL: baseURL), transport: transport)
    }
    private func session(account: Int = 7, revision: UInt64 = 1) throws -> MerchantOperationsSession {
        try .init(accountID: account, epoch: 1, token: "synthetic-token", storageNamespace: "synthetic", viewerRevision: revision)
    }
    private func reader(_ transport: NPCAccessParityTransport, current: @escaping () -> MerchantOperationsSession?) throws -> MerchantOperationsSessionReader {
        .init(service: try service(transport), currentSession: current)
    }
    func testRoleNameCannotSubstituteForExplicitProfileWrite() throws {
        for role in MerchantAccess.Role.allCases {
            XCTAssertFalse(try access([], role: role.rawValue).allows(.character))
        }
        XCTAssertFalse(try access(["merchant:coop:manage", "merchant:basic:read", "merchant:project:manage"]).allows(.character))
        XCTAssertFalse(try access(["merchant:profile:write ", "MERCHANT:PROFILE:WRITE"]).allows(.character))
    }
    func testExplicitProfileWriteAllowsActiveDelegatesWithoutGrantingOtherFunctions() throws {
        for role in MerchantAccess.Role.allCases {
            let value = try access(["merchant:profile:write"], role: role.rawValue)
            XCTAssertTrue(value.allows(.character))
            XCTAssertFalse(value.allows(.cooperation)); XCTAssertFalse(value.allows(.npcMapPoint))
            XCTAssertFalse(value.allows(.template(nil)))
        }
        XCTAssertFalse(try access(["merchant:profile:write"], active: false).allows(.character))
    }
    func testUnknownActiveRoleCannotDecodeEvenWithExplicitProfileWrite() {
        for role in ["MERCHANT_STAFF", "UNKNOWN", ""] {
            for permissions in [[], ["merchant:profile:write"]] as [[String]] {
                XCTAssertThrowsError(try access(permissions, role: role)) { error in
                    guard case DecodingError.dataCorrupted = error else {
                        return XCTFail("Unknown active identities must fail decoding: \(error)")
                    }
                }
            }
        }
    }
    func testLegacyAssetsAndCityPolicyIsUnchanged() throws {
        let value = try access([])
        XCTAssertTrue(value.allows(.assets)); XCTAssertTrue(value.allows(.cityNodes))
    }
    func testDeniedCharacterReadUsesZeroTransportRequests() async throws {
        for permissions in [[], ["merchant:coop:manage"]] as [[String]] {
            let transport = NPCAccessParityTransport()
            do {
                _ = try await service(transport).document(.character, access: access(permissions), token: "synthetic-token")
                XCTFail("Missing PROFILE_WRITE must be rejected before the profile request")
            } catch { XCTAssertEqual(error as? MerchantOperationsFailure, .accessDenied) }
            XCTAssertTrue(transport.requests.isEmpty)
        }
    }
    func testAuthorizedCharacterReadRetainsExactEndpointAndBody() async throws {
        let transport = NPCAccessParityTransport(); transport.replies = [profile]
        let value = try await service(transport).document(.character, access: access(["merchant:profile:write"]), token: "synthetic-token")
        guard case .draft(.character(let character)) = value else { return XCTFail() }
        XCTAssertEqual(character.name, "Guide")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(transport.requests.count, 1); XCTAssertEqual(request.url?.path, "/contract/api/merchant/npc/profile")
        XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.httpBody, Data("{}".utf8))
    }
    func testSessionReaderRechecksAccessAndNeverRequestsDeniedProfile() async throws {
        let transport = NPCAccessParityTransport(); transport.replies = [try envelope([])]
        let captured = try session(), reader = try self.reader(transport, current: { captured })
        do { _ = try await reader.document(.character); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantOperationsFailure, .accessDenied) }
        XCTAssertEqual(transport.requests.map { $0.url!.lastPathComponent }, ["me"])
    }
    func testRevokedAccessReloadClearsPreviouslyLoadedCharacter() async throws {
        let transport = NPCAccessParityTransport()
        transport.replies = [try envelope(["merchant:profile:write"]), profile, try envelope([])]
        let captured = try session(), reader = try self.reader(transport, current: { captured })
        let coordinator = MerchantOperationsCoordinator(reader: reader, destination: .character)
        await coordinator.load(); XCTAssertNotNil(coordinator.document)
        await coordinator.load()
        XCTAssertNil(coordinator.document); XCTAssertNil(coordinator.draft); XCTAssertNil(coordinator.baseline)
        XCTAssertFalse(coordinator.canReview)
        XCTAssertEqual(transport.requests.map { $0.url!.lastPathComponent }, ["me", "profile", "me"])
    }
    func testAccountChangeDuringAccessReadStopsBeforeProfileRequest() async throws {
        let transport = NPCAccessParityTransport(); transport.replies = [try envelope(["merchant:profile:write"])]
        var current: MerchantOperationsSession? = try session()
        let replacement = try session(account: 8), reader = try self.reader(transport, current: { current })
        transport.onSend = { _ in current = replacement }
        do { _ = try await reader.document(.character); XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(transport.requests.count, 1)
    }
    func testAccessRevisionChangeDuringProfileReadDiscardsLateDocument() async throws {
        let transport = NPCAccessParityTransport()
        transport.replies = [try envelope(["merchant:profile:write"]), profile]
        var current: MerchantOperationsSession? = try session()
        let replacement = try session(revision: 2), reader = try self.reader(transport, current: { current })
        transport.onSend = { count in if count == 2 { current = replacement } }
        let coordinator = MerchantOperationsCoordinator(reader: reader, destination: .character)
        await coordinator.load()
        XCTAssertNil(coordinator.document); XCTAssertNil(coordinator.draft); XCTAssertNil(coordinator.baseline)
        XCTAssertFalse(coordinator.canReview); XCTAssertEqual(transport.requests.count, 2)
    }
    func testServerRevocationDuringProfileReadDoesNotPresentACharacter() async throws {
        let transport = NPCAccessParityTransport()
        transport.replies = [try envelope(["merchant:profile:write"]), #"{"code":403,"msg":"Access revoked"}"#]
        let captured = try session(), reader = try self.reader(transport, current: { captured })
        let coordinator = MerchantOperationsCoordinator(reader: reader, destination: .character)
        await coordinator.load()
        XCTAssertNil(coordinator.document); XCTAssertNil(coordinator.draft); XCTAssertNil(coordinator.baseline)
        XCTAssertNotNil(coordinator.issue); XCTAssertFalse(coordinator.canReview)
    }
    func testSignOutDuringProfileReadDiscardsLateDocument() async throws {
        let transport = NPCAccessParityTransport()
        transport.replies = [try envelope(["merchant:profile:write"]), profile]
        var current: MerchantOperationsSession? = try session()
        let reader = try self.reader(transport, current: { current })
        transport.onSend = { count in if count == 2 { current = nil } }
        let coordinator = MerchantOperationsCoordinator(reader: reader, destination: .character)
        await coordinator.load()
        XCTAssertNil(coordinator.document); XCTAssertNil(coordinator.draft); XCTAssertFalse(coordinator.canReview)
    }
    func testWritePreflightUsesLatestPermissionBeforeProfileOrJournal() async throws {
        let transport = NPCAccessParityTransport(); transport.replies = [try envelope([])]
        let journal = NPCAccessParityJournal()
        let original = try JSONDecoder().decode(MerchantStoreCharacter.self, from: Data(#"{"name":"Guide","avatar":"px1:p01"}"#.utf8))
        var changed = original; changed.name = "Changed"
        let approval = try OperationEndpointApproval(baseURL: baseURL, namespace: "synthetic", accountID: 7, paths: ["api/merchant/npc/save"])
        do {
            _ = try await service(transport).save(.character(changed), token: "synthetic-token", approval: approval,
                namespace: "synthetic", accountID: 7, baseline: .character(original), journal: journal, checkSession: {})
            XCTFail("An endpoint approval cannot supply the missing merchant permission")
        } catch { XCTAssertEqual(error as? MerchantOperationsFailure, .accessDenied) }
        XCTAssertEqual(transport.requests.map { $0.url!.lastPathComponent }, ["me"])
        XCTAssertEqual(journal.writes, 0); XCTAssertNil(journal.record)
    }
    func testProfileWritePermissionDoesNotEnableOrdinaryReaderWrites() async throws {
        let transport = NPCAccessParityTransport(), captured = try session()
        let reader = try self.reader(transport, current: { captured })
        XCTAssertFalse(reader.canSave)
        do { try await reader.saveReviewed(.character(.init()), baseline: .character(.init())); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantOperationsFailure, .liveWritesDisabled) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
}
