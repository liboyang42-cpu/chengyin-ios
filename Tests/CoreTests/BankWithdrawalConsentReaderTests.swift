import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class BankWithdrawalConsentReaderTests: XCTestCase {
    private let base = URL(string: "https://example.com")!
    private func context() throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: base, role: "merchant", session: try .init(accountID: 7, epoch: 1, namespace: "fixture", token: "synthetic"))
    }
    private func consent(_ version: String = "current-v2", event: String = "AGREE", extra: String = "") -> Data {
        Data("{\"code\":200,\"data\":{\"docType\":\"bank_account_collection\",\"scene\":\"withdrawal\",\"docVersion\":\"\(version)\",\"eventType\":\"\(event)\"\(extra)}}".utf8)
    }
    func testCurrentDocumentAndLatestConsentMustMatchWithoutWritingConsent() async throws {
        let context = try context(), fake = BankConsentFakeTransport(), provider = BankCurrentDocumentFake()
        fake.data = consent()
        let reader = BankWithdrawalConsentReader(configuration: try .init(baseURL: base), transport: fake, provider: provider,
            captured: context, scope: .init(namespace: "fixture", accountID: 7, epoch: UUID()), current: { context })
        XCTAssertNil(reader.evidence); XCTAssertEqual(provider.calls, 0); XCTAssertTrue(fake.requests.isEmpty)
        try await reader.refresh()
        XCTAssertTrue(reader.evidence?.valid == true); XCTAssertEqual(reader.document?.version, "current-v2")
        XCTAssertEqual(fake.requests.count, 1); XCTAssertEqual(fake.requests[0].url?.path, "/api/compliance/consents/latest")
        let fields = try JSONSerialization.jsonObject(with: fake.requests[0].httpBody!) as! [String: String]
        XCTAssertEqual(fields, ["docType": "bank_account_collection", "scene": "withdrawal"])
        XCTAssertNil(fields["eventType"]); XCTAssertNil(fields["docVersion"])
    }
    func testOldRevokedOrScopedConsentCannotBeReused() async throws {
        let context = try context(), fake = BankConsentFakeTransport(), provider = BankCurrentDocumentFake()
        let reader = BankWithdrawalConsentReader(configuration: try .init(baseURL: base), transport: fake, provider: provider,
            captured: context, scope: .init(namespace: "fixture", accountID: 7, epoch: UUID()), current: { context })
        for data in [consent("old-v1"), consent(event: "REVOKE"), consent(extra: ",\"scopeType\":\"MERCHANT\",\"scopeId\":9")] {
            fake.data = data
            do { try await reader.refresh(); XCTFail() } catch { XCTAssertEqual(error as? BankWithdrawalFailure, .consentRequired) }
            XCTAssertNil(reader.evidence)
        }
        XCTAssertEqual(provider.calls, 3)
    }
    func testDocumentProviderFailureNeverGuessesVersionFromConsent() async throws {
        let context = try context(), fake = BankConsentFakeTransport(), provider = BankCurrentDocumentFake(); provider.unavailable = true
        let reader = BankWithdrawalConsentReader(configuration: try .init(baseURL: base), transport: fake, provider: provider,
            captured: context, scope: .init(namespace: "fixture", accountID: 7, epoch: UUID()), current: { context })
        do { try await reader.refresh(); XCTFail() } catch {}
        XCTAssertTrue(fake.requests.isEmpty); XCTAssertNil(reader.evidence); XCTAssertNil(reader.document)
    }
    func testLogoutDuringDocumentReadPreventsConsentRequest() async throws {
        var current: RuntimeDependencyContext? = try context(); let captured = current!, fake = BankConsentFakeTransport(), provider = BankCurrentDocumentFake()
        provider.onRead = { current = nil }
        let reader = BankWithdrawalConsentReader(configuration: try .init(baseURL: base), transport: fake, provider: provider,
            captured: captured, scope: .init(namespace: "fixture", accountID: 7, epoch: UUID()), current: { current })
        do { try await reader.refresh(); XCTFail() } catch {}
        XCTAssertTrue(fake.requests.isEmpty); XCTAssertNil(reader.evidence)
    }
    func testRefreshClearsPriorConsentBeforeFailure() async throws {
        let context = try context(), fake = BankConsentFakeTransport(), provider = BankCurrentDocumentFake(); fake.data = consent()
        let reader = BankWithdrawalConsentReader(configuration: try .init(baseURL: base), transport: fake, provider: provider,
            captured: context, scope: .init(namespace: "fixture", accountID: 7, epoch: UUID()), current: { context })
        try await reader.refresh(); XCTAssertNotNil(reader.evidence)
        fake.data = consent(event: "REVOKE")
        do { try await reader.refresh(); XCTFail() } catch {}
        XCTAssertNil(reader.evidence)
    }
    func testDynamicBankPathsRequireValidatedIDAndIndependentActions() throws {
        let context = try context(), fake = BankConsentFakeTransport()
        let policy = try BusinessRuntimeConfiguration(market: .china, baseURL: base, namespace: "fixture", accountID: 7,
            routes: [.bankPrepare: [.post("api/fund/preflight/bank-withdrawal")]], bankChallengeActions: [.confirm])
        let factory = try XCTUnwrap(BusinessRuntimeFactory(configuration: policy, api: .init(baseURL: base), transport: fake, current: { context }))
        let routes = BankWithdrawalRuntimeRoutes(factory: factory)
        XCTAssertNil(routes.approval(path: "api/fund/preflight/51/confirm"))
        routes.validatedChallenge(51)
        XCTAssertNotNil(routes.approval(path: "api/fund/preflight/51/confirm"))
        XCTAssertNil(routes.approval(path: "api/fund/preflight/52/confirm"))
        XCTAssertNil(routes.approval(path: "api/fund/preflight/51/reject"))
        XCTAssertNil(routes.approval(path: "api/withdrawal/create"))
        routes.validatedChallenge(nil); XCTAssertTrue(routes.dynamicRoutes.isEmpty)
    }
    func testCurrentDocumentCannotBeEmptyOrCredentialBearing() throws {
        XCTAssertThrowsError(try BankWithdrawalCurrentDocument(version: "", officialURL: URL(string: "https://example.com/legal")!))
        XCTAssertThrowsError(try BankWithdrawalCurrentDocument(version: "v2", officialURL: URL(string: "https://secret@example.com/legal")!))
    }
}
@MainActor private final class BankCurrentDocumentFake: BankWithdrawalCurrentDocumentProviding {
    var calls = 0; var unavailable = false; var onRead: (() -> Void)?
    func currentDocument(context: RuntimeDependencyContext) async throws -> BankWithdrawalCurrentDocument {
        calls += 1; onRead?()
        if unavailable { throw BankWithdrawalFailure.consentRequired }
        return try .init(version: "current-v2", officialURL: URL(string: "https://example.com/legal/bank")!)
    }
}
@MainActor private final class BankConsentFakeTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var data = Data(#"{"code":200,"data":null}"#.utf8)
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (data, 200) }
}
