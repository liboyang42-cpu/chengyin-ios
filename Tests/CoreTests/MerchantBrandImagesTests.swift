import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private func brandImages(_ raw: String = #"{"id":31,"derivatives":"https://example.test/one.png,/legacy.png,https://example.test/two.png,https://example.test/one.png"}"#) throws -> MerchantBrandImages {
    try JSONDecoder().decode(MerchantBrandImages.self, from: Data(raw.utf8))
}
final class MerchantBrandImagesContractTests: XCTestCase {
    func testSourceOrderDuplicatesAndUnsupportedCandidatesArePreserved() throws {
        let value = try brandImages(); XCTAssertEqual(value.merchantID, 31)
        XCTAssertEqual(value.items.map(\.id), [0, 1, 2, 3]); XCTAssertNil(value.items[1].url)
        XCTAssertEqual(value.items[0].url, value.items[3].url)
    }
    func testMissingNullEmptyAndTextMerchandiseAreRealEmpty() throws {
        for raw in [#"{"id":31}"#, #"{"id":31,"derivatives":null}"#, #"{"id":31,"derivatives":""}"#,
                    #"{"id":31,"derivatives":"Postcards, mugs"}"#] { XCTAssertTrue(try brandImages(raw).items.isEmpty) }
    }
    func testMalformedOuterFieldOrIdentityIsNotEmptySuccess() {
        for raw in ["null", "[]", "{}", #"{"id":0}"#, #"{"id":"31"}"#,
                    #"{"id":31,"derivatives":[]}"#, #"{"id":31,"derivatives":3}"#] { XCTAssertThrowsError(try brandImages(raw)) }
    }
    func testUnsafeImageReferencesCannotCreateURL() throws {
        let raw = #"{"id":31,"derivatives":"http://example.test/a,/relative.png,//example.test/a,https://user:secret@example.test/a,https:///no-host,https://example.test/a\n.png,https://example.test/good.png"}"#
        let value = try brandImages(raw); XCTAssertEqual(value.items.count, 7)
        XCTAssertTrue(value.items.prefix(6).allSatisfy { $0.url == nil }); XCTAssertNotNil(value.items.last?.url)
    }
    func testWhitespaceDoesNotBreakCSVAndUnknownFieldsAreNotImages() throws {
        let value = try brandImages(#"{"id":31,"derivatives":"  https://example.test/a.png , text , https://example.test/b.png ","businessLicense":"https://example.test/private.png"}"#)
        XCTAssertEqual(value.items.count, 2); XCTAssertEqual(value.items[0].url?.absoluteString, "https://example.test/a.png")
    }
}

@MainActor private final class BrandReader: MerchantOperationsReading {
    let fixture = MerchantOperationsFixtureReader()
    var scope: UUID { fixture.scope }
    var isConfigured: Bool { true }
    var isAuthenticated: Bool { fixture.isAuthenticated }
    var isOfflineExample: Bool { true }
    var value = try! brandImages()
    var failure: APIError?
    var suspend = false
    var pending: [CheckedContinuation<MerchantBrandImages, Error>] = []
    func access() async throws -> MerchantOperationsAccess { try await fixture.access() }
    func document(_ destination: MerchantOperationsDestination) async throws -> MerchantOperationsDocument { try await fixture.document(destination) }
    func saveExample(_ draft: MerchantOperationsDraft) async throws { try await fixture.saveExample(draft) }
    func brandImages() async throws -> MerchantBrandImages {
        if let failure { throw failure }
        if suspend { return try await withCheckedThrowingContinuation { pending.append($0) } }
        return value
    }
}
@MainActor final class MerchantBrandImagesSessionTests: XCTestCase {
    private func setup() async throws -> (BrandReader, MerchantOperationsCoordinator, MerchantBrandImagesSession) {
        let reader = BrandReader(); let owner = MerchantOperationsCoordinator(reader: reader, destination: .profile)
        await owner.load(); return (reader, owner, try XCTUnwrap(MerchantBrandImagesSession(owner: owner)))
    }
    func testViewingReadsSavedSourceWithoutChangingDirtyProfile() async throws {
        let (reader, owner, _) = try await setup()
        guard case .profile(var draft) = owner.draft else { return XCTFail() }
        draft.derivatives = "https://example.test/unsaved.png"; owner.edit(.profile(draft))
        let session = try XCTUnwrap(MerchantBrandImagesSession(owner: owner)); await session.reload()
        XCTAssertTrue(session.select(0)); XCTAssertEqual(session.currentURL?.absoluteString, "https://example.test/one.png")
        XCTAssertEqual(owner.draft, .profile(draft)); XCTAssertTrue(owner.isDirty); XCTAssertEqual(reader.fixture.saveCount, 0)
    }
    func testZoomNavigationAndImageRetryRetireOldCallbacks() async throws {
        let (reader, owner, session) = try await setup(); defer { withExtendedLifetime((reader, owner)) {} }; await session.reload()
        XCTAssertTrue(session.select(0)); let first = session.imageGeneration
        XCTAssertTrue(session.setZoom(50, ticket: first, index: 0)); XCTAssertEqual(session.zoom, 5)
        XCTAssertFalse(session.setZoom(.nan, ticket: first, index: 0)); XCTAssertNil(session.previousIndex); XCTAssertEqual(session.nextIndex, 2)
        XCTAssertFalse(session.select(1)); XCTAssertTrue(session.select(2)); XCTAssertEqual(session.zoom, 1)
        XCTAssertFalse(session.setZoom(4, ticket: first, index: 0)); XCTAssertEqual(session.previousIndex, 0)
        let second = session.imageGeneration; session.retryImage(ticket: second, index: 2)
        XCTAssertFalse(session.imageIsCurrent(second, index: 2)); XCTAssertEqual(session.zoom, 1)
        session.closeImage(); XCTAssertNil(session.currentURL)
    }
    func testReloadRetiresImageAndUsesLatestSource() async throws {
        let (reader, owner, session) = try await setup(); defer { withExtendedLifetime(owner) {} }; await session.reload(); XCTAssertTrue(session.select(2))
        let old = session.imageGeneration; reader.value = try brandImages(#"{"id":31,"derivatives":"https://example.test/new.png"}"#)
        await session.reload(); XCTAssertNil(session.selectedIndex); XCTAssertEqual(session.items.count, 1)
        XCTAssertFalse(session.imageIsCurrent(old, index: 2)); XCTAssertTrue(session.select(0))
        XCTAssertEqual(session.currentURL?.lastPathComponent, "new.png")
    }
    func testFailedLoadIsNotEmptyAndRetryCanRecover() async throws {
        let (reader, owner, session) = try await setup(); defer { withExtendedLifetime(owner) {} }; reader.failure = .httpStatus(503); await session.reload()
        XCTAssertNil(session.document); XCTAssertNotNil(session.issue)
        reader.failure = nil; reader.value = try brandImages(#"{"id":31}"#); await session.reload()
        XCTAssertNotNil(session.document); XCTAssertNil(session.issue); XCTAssertTrue(session.items.isEmpty)
    }
    func testWrongMerchantSourceIsRejected() async throws {
        let (reader, owner, session) = try await setup(); defer { withExtendedLifetime(owner) {} }; reader.value = try brandImages(#"{"id":32,"derivatives":"https://example.test/a"}"#)
        await session.reload(); XCTAssertNil(session.document); XCTAssertEqual(session.issue, .key("merchant.invalidResponse"))
    }
    func testDraftChangeReviewAndScopeChangeInvalidateViewer() async throws {
        let (reader, owner, session) = try await setup(); await session.reload(); XCTAssertTrue(session.select(0))
        guard case .profile(var draft) = owner.draft else { return XCTFail() }
        draft.name += " changed"; owner.edit(.profile(draft)); XCTAssertFalse(session.isCurrent); XCTAssertNil(session.currentURL)
        let second = try XCTUnwrap(MerchantBrandImagesSession(owner: owner)); await second.reload(); owner.prepare()
        XCTAssertFalse(second.isCurrent); owner.cancelConfirmation()
        let third = try XCTUnwrap(MerchantBrandImagesSession(owner: owner)); await third.reload(); reader.fixture.signOut()
        XCTAssertFalse(third.isCurrent); XCTAssertTrue(third.items.isEmpty)
    }
    func testRetirementRejectsLateSuccessfulRead() async throws {
        let (reader, owner, session) = try await setup(); defer { withExtendedLifetime(owner) {} }; reader.suspend = true
        let load = Task { await session.reload() }; while reader.pending.isEmpty { await Task.yield() }
        session.retire(); reader.pending.removeFirst().resume(returning: reader.value); await load.value
        XCTAssertFalse(session.isCurrent); XCTAssertNil(session.document); XCTAssertNil(session.issue); XCTAssertFalse(session.isLoading)
    }
    func testNewReloadSupersedesOldReadWithoutClearingItsBusyState() async throws {
        let (reader, owner, session) = try await setup(); defer { withExtendedLifetime(owner) {} }; reader.suspend = true
        let first = Task { await session.reload() }; while reader.pending.count < 1 { await Task.yield() }
        let second = Task { await session.reload() }; while reader.pending.count < 2 { await Task.yield() }
        reader.pending.removeFirst().resume(returning: reader.value); await first.value
        XCTAssertNil(session.document); XCTAssertTrue(session.isLoading)
        reader.pending.removeFirst().resume(returning: try brandImages(#"{"id":31}"#)); await second.value
        XCTAssertNotNil(session.document); XCTAssertTrue(session.items.isEmpty); XCTAssertFalse(session.isLoading)
    }
    func testInvalidOwnerCannotStartAndRetiredSessionCannotReopen() async throws {
        let (reader, owner, session) = try await setup(); session.retire(); await session.reload(); XCTAssertFalse(session.select(0))
        let other = MerchantOperationsCoordinator(reader: reader, destination: .decor); await other.load()
        XCTAssertNil(MerchantBrandImagesSession(owner: other)); owner.invalidate(); XCTAssertNil(MerchantBrandImagesSession(owner: owner))
    }
}

private final class BrandTransport: HTTPTransport, @unchecked Sendable {
    var replies: [String] = []
    var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); guard !replies.isEmpty else { throw APIError.httpStatus(503) }
        return (Data(replies.removeFirst().utf8), 200)
    }
}
@MainActor final class MerchantBrandImagesServiceTests: XCTestCase {
    private let access = #"{"code":200,"data":{"active":true,"merchant":{"id":31},"roleCode":"MERCHANT_OWNER","permissions":["merchant:profile:write","merchant:coop:manage"]}}"#
    private func reader(_ transport: BrandTransport) throws -> MerchantOperationsSessionReader {
        let session = try MerchantOperationsSession(accountID: 7, epoch: 1, token: "synthetic-token")
        let config = try APIConfiguration(baseURL: URL(string: "https://example.test/prod-api")!)
        return .init(service: .init(configuration: config, transport: transport), currentSession: { session })
    }
    func testExistingAuthorizedReadOnlyPOSTAndExactRequestBody() async throws {
        let transport = BrandTransport(); transport.replies = [access, #"{"code":200,"data":{"id":31,"derivatives":"https://example.test/a.png"}}"#]
        let reader = try reader(transport); let value = try await reader.brandImages(); XCTAssertEqual(value.items.count, 1)
        XCTAssertFalse(reader.canSave); XCTAssertEqual(transport.requests.map { $0.url!.path }, ["/prod-api/api/merchant/access/me", "/prod-api/api/merchant/coop-profile"])
        let request = try XCTUnwrap(transport.requests.last); XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.httpBody, Data("{}".utf8)); XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }
    func testEitherMissingExistingGrantStopsBeforePrivateRead() async throws {
        for permission in ["merchant:profile:write", "merchant:coop:manage"] {
            let transport = BrandTransport(); transport.replies = [access.replacingOccurrences(of: permission, with: "merchant:basic:read")]
            do { _ = try await reader(transport).brandImages(); XCTFail() }
            catch { XCTAssertEqual(error as? MerchantOperationsFailure, .accessDenied) }
            XCTAssertEqual(transport.requests.count, 1)
        }
    }
    func testWrongMerchantAndMalformedFieldCannotReturnImages() async throws {
        for result in [#"{"id":32,"derivatives":"https://example.test/a"}"#, #"{"id":31,"derivatives":[]}"#] {
            let transport = BrandTransport(); transport.replies = [access, "{\"code\":200,\"data\":" + result + "}"]
            do { _ = try await reader(transport).brandImages(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
    }
    func testServerDenialRemainsDeniedWithoutWriteOrAlternateEndpoint() async throws {
        let transport = BrandTransport(); transport.replies = [access, #"{"code":403,"msg":"Denied"}"#]
        do { _ = try await reader(transport).brandImages(); XCTFail() } catch { XCTAssertEqual(error as? MerchantOperationsFailure, .accessDenied) }
        XCTAssertEqual(transport.requests.count, 2)
    }
}
