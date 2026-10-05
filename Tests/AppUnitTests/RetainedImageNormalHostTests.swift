import XCTest
import UIKit
@testable import Questify

/// Requires the same separate iOS application unit-test target as the sanitizer tests.
/// These tests never open PhotosUI, read external files or make HTTP requests.
@MainActor final class RetainedImageNormalHostTests: XCTestCase {
    private final class NoNetwork: HTTPTransport {
        var calls = 0
        func send(_ request: URLRequest) async throws -> (Data, Int) { calls += 1; throw APIError.notConfigured }
    }
    @MainActor private final class Credentials {
        var value: RetainedImageHostCredentials? = RetainedImageHostCredentials(accountID: 8, sessionVersion: 1,
            realm: "https://api.example.com/", namespace: "test-namespace", token: "fake-session-token")
    }
    @MainActor private final class Reader: MerchantOperationsReading {
        var scope = UUID()
        let isConfigured = true, isOfflineExample = false, canSave = false
        var isAuthenticated = true
        var grant: MerchantOperationsAccess
        var value: MerchantOperationsDocument
        init(templateID: Int? = nil, template: Bool = false) throws {
            grant = try JSONDecoder().decode(MerchantOperationsAccess.self, from: Data(#"{"active":true,"merchant":{"id":41},"roleCode":"MERCHANT_OWNER","permissions":["merchant:profile:write","merchant:project:manage"]}"#.utf8))
            if template { var draft = MerchantNodeTemplate(); draft.id = templateID; value = .draft(.template(draft)) }
            else { value = .draft(.profile(try JSONDecoder().decode(MerchantStoreProfile.self, from: Data(#"{"id":41,"name":"Store"}"#.utf8)))) }
        }
        func access() async throws -> MerchantOperationsAccess { grant }
        func document(_ destination: MerchantOperationsDestination) async throws -> MerchantOperationsDocument { value }
        func saveExample(_ draft: MerchantOperationsDraft) async throws { throw MerchantOperationsFailure.liveWritesDisabled }
    }
    @MainActor private final class JournalStorage {
        var values: [String: Data] = [:]
        func journal() -> StoredImageUploadJournal {
            StoredImageUploadJournal(read: { self.values[$0] }, write: { self.values[$1] = $0 })
        }
    }
    private func setup(reader: Reader, destination: MerchantOperationsDestination = .profile) throws -> (MerchantOperationsViewModel, Credentials, NoNetwork, RetainedImageContextCache) {
        let credentials = Credentials(), network = NoNetwork()
        let cache = RetainedImageContextCache(configuration: try APIConfiguration(baseURL: URL(string: "https://api.example.com/")!),
            transport: network, pickerHost: RetainedImagePickerHost(), journal: JournalStorage().journal(), currentCredentials: { credentials.value })
        let model = MerchantOperationsViewModel(reader: reader, destination: destination, imageHost: MerchantRetainedImageHost(cache: cache))
        return (model, credentials, network, cache)
    }
    func testNormalFactoryCachesOwnerAndUsesMerchantRowRatherThanAccount() async throws {
        let reader = try Reader(), (model, _, network, _) = try setup(reader: reader)
        await model.load()
        let a = try XCTUnwrap(model.imageContext(.logo)), b = try XCTUnwrap(model.imageContext(.logo))
        XCTAssertTrue(a.uploads === b.uploads); XCTAssertTrue(a.picker === b.picker)
        XCTAssertEqual(a.scope.accountID, 8); XCTAssertEqual(a.scope.destination, .merchant(merchantRowID: 41, field: .logo))
        XCTAssertEqual(a.scope.epoch, reader.scope); XCTAssertFalse(a.picker.enabled)
        XCTAssertFalse(a.uploads.uploader.isConfigured); XCTAssertEqual(network.calls, 0)
    }
    func testDraftChangeInvalidatesCapturedContextAndOtherFieldsStayUnavailable() async throws {
        let (model, _, _, _) = try setup(reader: Reader()); await model.load()
        let old = try XCTUnwrap(model.imageContext(.logo))
        guard case .profile(var draft) = model.coordinator.draft else { return XCTFail() }
        draft.name = "Changed locally"; model.edit(.profile(draft))
        XCTAssertNil(old.currentScope()); XCTAssertNil(model.imageContext(.avatar))
        let next = try XCTUnwrap(model.imageContext(.logo)); XCTAssertNotEqual(next.scope.accessRevision, old.scope.accessRevision)
    }
    func testTemplateExistingAndNewDraftHaveExactResourceFences() async throws {
        let existing = try Reader(templateID: 64, template: true)
        let (model, _, _, _) = try setup(reader: existing, destination: .template(64)); await model.load()
        let context = try XCTUnwrap(model.imageContext(.imgUrl)); XCTAssertEqual(context.scope.resourceID, 64)
        XCTAssertNotNil(context.scope.accessRevision); XCTAssertNil(model.imageContext(.logo))
        let (new, _, _, _) = try setup(reader: Reader(template: true), destination: .template(nil)); await new.load()
        let fresh = try XCTUnwrap(new.imageContext(.imgUrl)); XCTAssertNil(fresh.scope.resourceID); XCTAssertNotNil(fresh.scope.accessRevision)
        XCTAssertNotEqual(context.scope.accessRevision, fresh.scope.accessRevision)
    }
    func testAccountAndReaderScopeChangesFenceOldContextImmediately() async throws {
        let reader = try Reader(), (model, credentials, _, _) = try setup(reader: reader); await model.load()
        let old = try XCTUnwrap(model.imageContext(.logo)); reader.scope = UUID()
        XCTAssertNil(old.currentScope()); XCTAssertNil(model.imageContext(.logo))
        await model.load(); let next = try XCTUnwrap(model.imageContext(.logo)); credentials.value = nil
        XCTAssertNil(next.currentScope()); XCTAssertNil(model.imageContext(.logo))
    }
    func testAccessRevocationAndLeaveClearOwner() async throws {
        let reader = try Reader(), (model, _, _, _) = try setup(reader: reader); await model.load()
        let old = try XCTUnwrap(model.imageContext(.logo))
        reader.grant = try JSONDecoder().decode(MerchantOperationsAccess.self, from: Data(#"{"active":false}"#.utf8))
        await model.load(); XCTAssertNil(old.currentScope()); XCTAssertNil(model.imageContext(.logo))
        model.leaveImages(); XCTAssertNil(model.imageContext(.logo))
    }
    func testPublicReviewNormalCompositionIsEntirelyDormant() async throws {
        let (_, credentials, network, cache) = try setup(reader: Reader())
        let session = try PublicMerchantReviewSession(accountID: 8, scope: UUID(), realm: "https://api.example.com/", token: credentials.value!.token)
        let host = RetainedPublicMerchantReviewHost(configuration: try APIConfiguration(baseURL: URL(string: session.realm)!),
            transport: network, cache: cache, currentSession: { session })
        XCTAssertFalse(host.reader.isConfigured); XCTAssertFalse(host.writer.isConfigured); XCTAssertFalse(host.imageReader.enabled)
        let target = PublicMerchantReviewTarget(merchantRowID: PublicMerchantRowID(41)!, ownerMemberID: PublicMerchantOwnerID(73)!)
        do { _ = try await host.reader.page(target, page: 1); XCTFail() }
        catch { XCTAssertEqual(error as? PublicMerchantHomeFailure, .notConfigured) }
        XCTAssertEqual(network.calls, 0)
    }
}
