import XCTest
@testable import Questify

@MainActor final class MerchantOnboardingLicenseRemovalTests: XCTestCase {
    @MainActor private final class Server: MerchantOnboardingServing {
        var isConfigured = true
        var identity: ProfileReadIdentity? = .init(accountID: 41, epoch: 1)
        var registered = true
        var uploads = 0, submits = 0
        var failUpload = false
        func application(expectedIdentity: ProfileReadIdentity) async throws -> MerchantOnboardingSnapshot { .none }
        func identityRegistered(expectedIdentity: ProfileReadIdentity) async throws -> Bool { registered }
        func uploadLicense(_ image: MerchantOnboardingImage, expectedIdentity: ProfileReadIdentity) async throws -> MerchantOnboardingLicense {
            uploads += 1
            if failUpload { throw MerchantOnboardingWriteError.outcomeUnknown }
            return try .init(serverURL: "https://fixtures.example/replacement.jpg")
        }
        func submit(_ draft: MerchantOnboardingDraft, expectedIdentity: ProfileReadIdentity) async throws { submits += 1 }
    }
    private func ready() async throws -> (MerchantOnboardingModel, Server) {
        let server = Server()
        let m = MerchantOnboardingModel(coordinator: .init(server: server)); m.reset(); await m.load(); await m.checkIdentity()
        m.draft.name = "Raw name "; m.draft.phone = "2025550100"; m.draft.address = "Example street"
        m.draft.businessTime = "Stored hours"; m.draft.description = "Raw\ntext"
        m.draft.license = try .init(serverURL: "https://fixtures.example/original.jpg")
        m.draft.brandImages = try .init(urls: ["https://fixtures.example/brand.jpg"])
        m.step = 3
        return (m, server)
    }
    func testCancelPreservesAllDraftBytesAndMakesTicketUnusable() async throws {
        let (m,s) = try await ready(); let before = m.draft, ticket = try XCTUnwrap(m.prepareLicenseRemoval())
        m.cancelLicenseRemoval(ticket); XCTAssertFalse(m.removeLicense(ticket)); XCTAssertEqual(m.draft,before)
        XCTAssertEqual(s.uploads,0); XCTAssertEqual(s.submits,0)
    }
    func testRemoveOnlyLicenseAndRequireReplacementBeforeNext() async throws {
        let (m,s) = try await ready(); var expected = m.draft; expected.license = nil
        let ticket = try XCTUnwrap(m.prepareLicenseRemoval()); XCTAssertTrue(m.removeLicense(ticket)); XCTAssertEqual(m.draft,expected)
        XCTAssertEqual(m.errorKey,"merchant.onboarding.required.license"); m.next(); XCTAssertEqual(m.step,3)
        XCTAssertFalse(m.removeLicense(ticket)); XCTAssertEqual(s.uploads,0); XCTAssertEqual(s.submits,0)
    }
    func testExistingUploadRestoresEligibilityWithoutRegistration() async throws {
        let (m,s) = try await ready(); XCTAssertTrue(m.removeLicense(try XCTUnwrap(m.prepareLicenseRemoval())))
        m.selectedImage = try .init(jpegData: Data([0xff,0xd8,0xff,0xd9])); await m.uploadSelected()
        XCTAssertEqual(m.draft.license?.url,"https://fixtures.example/replacement.jpg"); m.next(); XCTAssertEqual(m.step,4)
        XCTAssertEqual(s.uploads,1); XCTAssertEqual(s.submits,0)
    }
    func testFailedReplacementDoesNotRestoreOldLicenseOrAutoRetry() async throws {
        let (m,s) = try await ready(); XCTAssertTrue(m.removeLicense(try XCTUnwrap(m.prepareLicenseRemoval())))
        s.failUpload = true; m.selectedImage = try .init(jpegData: Data([0xff,0xd8,0xff,0xd9])); await m.uploadSelected()
        XCTAssertNil(m.draft.license); XCTAssertNotNil(m.selectedImage); XCTAssertEqual(m.errorKey,"merchant.onboarding.uploadFailed")
        XCTAssertEqual(s.uploads,1); XCTAssertEqual(s.submits,0)
    }
    func testDraftChangeAndReloadInvalidateTicket() async throws {
        let (m,_) = try await ready(); let old = try XCTUnwrap(m.prepareLicenseRemoval()); m.draft.name = "Newer"
        XCTAssertFalse(m.removeLicense(old)); XCTAssertNotNil(m.draft.license)
        let loaded = try XCTUnwrap(m.prepareLicenseRemoval()); await m.load(); XCTAssertFalse(m.removeLicense(loaded))
    }
    func testAccountEpochAndConfigurationChangesReject() async throws {
        for mode in 0...2 {
            let (m,s) = try await ready(); let ticket = try XCTUnwrap(m.prepareLicenseRemoval())
            if mode == 0 { s.identity = .init(accountID:42,epoch:1) }
            else if mode == 1 { s.identity = .init(accountID:41,epoch:2) }
            else { s.isConfigured = false }
            XCTAssertFalse(m.removeLicense(ticket)); XCTAssertNotNil(m.draft.license); XCTAssertEqual(s.submits,0)
        }
    }
    func testOldCancelCannotCancelNewConfirmation() async throws {
        let (m,_) = try await ready(); let old = try XCTUnwrap(m.prepareLicenseRemoval()), new = try XCTUnwrap(m.prepareLicenseRemoval())
        m.cancelLicenseRemoval(old); XCTAssertFalse(m.removeLicense(old)); XCTAssertTrue(m.removeLicense(new))
    }
    func testSubmitConfirmationAndSelectedPhotoBlockRemoval() async throws {
        let (m,_) = try await ready(); let ticket = try XCTUnwrap(m.prepareLicenseRemoval()); m.prepare()
        XCTAssertNotNil(m.confirmation); XCTAssertNil(m.prepareLicenseRemoval()); XCTAssertFalse(m.removeLicense(ticket))
        m.cancelConfirmation(); m.selectedImage = try .init(jpegData:Data([0xff,0xd8,0xff,0xd9])); XCTAssertNil(m.prepareLicenseRemoval())
    }
    func testIdentityRevocationAndPageLeaveReject() async throws {
        let (m,s) = try await ready(); let ticket = try XCTUnwrap(m.prepareLicenseRemoval()); s.registered = false; await m.checkIdentity()
        XCTAssertFalse(m.removeLicense(ticket)); XCTAssertNotNil(m.draft.license)
        s.registered = true; await m.checkIdentity(); let left = try XCTUnwrap(m.prepareLicenseRemoval()); m.leave(); XCTAssertFalse(m.removeLicense(left))
    }
    func testSuspensionCancellationKeepsDraft() async throws {
        let (m,_) = try await ready(); let before = m.draft, ticket = try XCTUnwrap(m.prepareLicenseRemoval())
        m.cancelLicenseRemoval(); XCTAssertFalse(m.removeLicense(ticket)); XCTAssertEqual(m.draft,before)
    }
}
