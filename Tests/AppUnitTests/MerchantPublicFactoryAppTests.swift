import XCTest
@testable import Questify

@MainActor final class MerchantPublicFactoryAppTests: XCTestCase {
    final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            return (Data(#"{"code":200,"data":{"id":31,"memberId":77,"npc":{"name":"Synthetic NPC"}}}"#.utf8), 200)
        }
    }
    final class Journal: OperationPendingJournal {
        func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { nil }
        func write(_ record: OperationPendingRecord) throws {}
        func clear(_ record: OperationPendingRecord) throws {}
    }
    func testNormalDormantDependenciesAndAppHomeRemainUnconfigured() async throws {
        let d = NativeRuntimeDependencies.dormant, wire = Wire()
        XCTAssertNil(d.merchantPublicApproval); XCTAssertFalse(d.merchantNPCGrants.chatAllowed)
        let context = try MerchantPublicHostContext(market: .china, baseURL: URL(string: "https://example.com/")!, namespace: "fixture", epoch: 1)
        XCTAssertNil(d.makeMerchantPublicFactory(api: try .init(baseURL: context.baseURL), journal: Journal(), current: { context }))
        let session = AppSession(runtimeDependencies: .init(transport: wire))
        let reader = session.publicMerchantHomeContext.reader
        XCTAssertFalse(reader.isConfigured)
        do { _ = try await reader.home(.legacyMerchantRowID(PublicMerchantRowID(31)!)); XCTFail() } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testNormalDependencyFactoryConstructsApprovedGuestReaderUsingInjectedHTTP() async throws {
        let wire = Wire(), url = URL(string: "https://example.com/prod-api/")!
        let context = try MerchantPublicHostContext(market: .china, baseURL: url, namespace: "fixture", epoch: 1)
        let approval = try MerchantPublicProductionApproval(market: .china, baseURL: url, namespace: "fixture", publicHomeRead: true)
        let d = NativeRuntimeDependencies(transport: wire, merchantPublicApproval: approval)
        let factory = try XCTUnwrap(d.makeMerchantPublicFactory(api: APIConfiguration(baseURL: url), journal: Journal(), current: { context }))
        let home = try await factory.homeReader.home(.ownerMemberID(PublicMerchantOwnerID(77)!))
        XCTAssertEqual(home.id, 31); XCTAssertEqual(wire.requests.count, 1)
        XCTAssertNil(wire.requests.first?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertFalse(factory.chatGrants.chatAllowed)
    }
    func testNormalDependencyFactoryRejectsAccountMismatchAndRetainedContextChanges() async throws {
        let wire = Wire(), url = URL(string: "https://example.com/")!
        var context: MerchantPublicHostContext? = try .init(market: .china, baseURL: url, namespace: "fixture", accountID: 9, epoch: 1, role: "user", token: "fixture-token")
        let approval = try MerchantPublicProductionApproval(market: .china, baseURL: url, namespace: "fixture", accountID: 9, publicHomeRead: true)
        let d = NativeRuntimeDependencies(transport: wire, merchantPublicApproval: approval)
        let factory = try XCTUnwrap(d.makeMerchantPublicFactory(api: APIConfiguration(baseURL: url), journal: Journal(), current: { context }))
        context = try .init(market: .china, baseURL: url, namespace: "fixture", accountID: 10, epoch: 2, role: "user", token: "next-token")
        XCTAssertFalse(factory.homeReader.isConfigured)
        XCTAssertNil(d.makeMerchantPublicFactory(api: try .init(baseURL: url), journal: Journal(), current: { context }))
        do { _ = try await factory.homeReader.home(.legacyMerchantRowID(PublicMerchantRowID(31)!)); XCTFail() } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
}
