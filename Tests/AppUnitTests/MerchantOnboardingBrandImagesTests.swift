import XCTest
@testable import Questify

@MainActor final class MerchantOnboardingBrandImageModelTests: XCTestCase {
    @MainActor private final class Server: MerchantOnboardingServing {
        var isConfigured = true
        var identity: ProfileReadIdentity? = .init(accountID: 41, epoch: 1)
        var registered = true
        var uploads = 0
        var drafts: [MerchantOnboardingDraft] = []
        var failUpload = false
        var holdUpload = false
        var waiter: CheckedContinuation<Void,Never>?
        func application(expectedIdentity: ProfileReadIdentity) async throws -> MerchantOnboardingSnapshot { .none }
        func identityRegistered(expectedIdentity: ProfileReadIdentity) async throws -> Bool { registered }
        func uploadLicense(_ image: MerchantOnboardingImage, expectedIdentity: ProfileReadIdentity) async throws -> MerchantOnboardingLicense {
            uploads += 1
            if holdUpload { await withCheckedContinuation { waiter = $0 } }
            if failUpload { throw MerchantOnboardingWriteError.outcomeUnknown }
            return try .init(serverURL: "https://fixtures.example/brand-\(uploads).jpg")
        }
        func submit(_ draft: MerchantOnboardingDraft, expectedIdentity: ProfileReadIdentity) async throws { drafts.append(draft) }
        func resume() { holdUpload=false;waiter?.resume();waiter=nil }
    }
    private func ready(registered: Bool = true) async throws -> (MerchantOnboardingModel,Server) {
        let server = Server();server.registered=registered
        let m=MerchantOnboardingModel(coordinator:.init(server:server));m.reset();await m.load();await m.checkIdentity()
        m.draft.name="Synthetic store";m.draft.phone="2025550100";m.draft.address="Example street";m.draft.businessTime="Stored hours"
        m.draft.license=try .init(serverURL:"https://fixtures.example/license.jpg");return(m,server)
    }
    private func image() throws -> MerchantOnboardingImage { try .init(jpegData:Data([0xff,0xd8,0xff,0xd9])) }
    private func select(_ m:MerchantOnboardingModel) async throws { let image=try image();await m.selectBrandImage(load:{image}) }
    private func upload(_ m:MerchantOnboardingModel) async throws { await m.uploadSelectedBrandImage(expectedID:try XCTUnwrap(m.selectedBrandImageID)) }
    func testSelectionIsLocalAndDoesNotChangeDraftOrLicense() async throws {
        let(m,s)=try await ready();let d=m.draft;try await select(m);XCTAssertEqual(m.draft,d);XCTAssertEqual(s.uploads,0);XCTAssertNotNil(m.selectedBrandImage)
    }
    func testExplicitUploadAppendsReturnedURLOnly() async throws {
        let(m,s)=try await ready();let license=m.draft.license;try await select(m);try await upload(m)
        XCTAssertEqual(s.uploads,1);XCTAssertEqual(m.draft.brandImages?.urls,["https://fixtures.example/brand-1.jpg"]);XCTAssertEqual(m.draft.license,license);XCTAssertNil(m.selectedBrandImage)
    }
    func testDiscardMakesNoRequestAndNoMutation() async throws {
        let(m,s)=try await ready();let d=m.draft;try await select(m);m.discardBrandImage();XCTAssertEqual(m.draft,d);XCTAssertEqual(s.uploads,0)
    }
    func testIdentityRequirementPreventsSelectionAndUpload() async throws {
        let(m,s)=try await ready(registered:false);try await select(m);XCTAssertNil(m.selectedBrandImage);XCTAssertFalse(m.canAddBrandImage);XCTAssertEqual(s.uploads,0)
    }
    func testFullListPreventsSeventhSelection() async throws {
        let(m,s)=try await ready();m.draft.brandImages=try .init(urls:Array(repeating:"https://fixtures.example/a",count:6));try await select(m)
        XCTAssertNil(m.selectedBrandImage);XCTAssertEqual(s.uploads,0)
    }
    func testStaleUploadConfirmationDoesNotDispatch() async throws {
        let(m,s)=try await ready();try await select(m);let old=try XCTUnwrap(m.selectedBrandImageID);m.discardBrandImage();try await select(m)
        await m.uploadSelectedBrandImage(expectedID:old);XCTAssertEqual(s.uploads,0)
    }
    func testDraftChangeAfterSelectionRejectsUpload() async throws {
        let(m,s)=try await ready();try await select(m);m.draft.name="Changed";try await upload(m);XCTAssertEqual(s.uploads,0)
    }
    func testAccountChangeRejectsUpload() async throws {
        let(m,s)=try await ready();try await select(m);s.identity = .init(accountID:42,epoch:2);try await upload(m);XCTAssertEqual(s.uploads,0)
    }
    func testResetDuringUploadRejectsLateURL() async throws {
        let(m,s)=try await ready();try await select(m);let id=try XCTUnwrap(m.selectedBrandImageID);s.holdUpload=true
        let task=Task{await m.uploadSelectedBrandImage(expectedID:id)};while s.waiter==nil{await Task.yield()}
        m.reset();s.resume();await task.value;XCTAssertNil(m.draft.brandImages);XCTAssertNil(m.selectedBrandImage)
    }
    func testUploadFailureDoesNotAutomaticallyRetryOrInventURL() async throws {
        let(m,s)=try await ready();try await select(m);s.failUpload=true;try await upload(m)
        XCTAssertEqual(s.uploads,1);XCTAssertNil(m.draft.brandImages);XCTAssertNotNil(m.selectedBrandImage);XCTAssertEqual(m.errorKey,"merchant.onboardingBrand.uploadFailed")
    }
    func testExplicitRetryUsesExistingUploaderAgain() async throws {
        let(m,s)=try await ready();try await select(m);s.failUpload=true;try await upload(m);s.failUpload=false;try await upload(m)
        XCTAssertEqual(s.uploads,2);XCTAssertEqual(m.draft.brandImages?.urls,["https://fixtures.example/brand-2.jpg"])
    }
    func testRemovingStaleIndexCannotRemoveReplacementImage() async throws {
        let(m,s)=try await ready();let old=try MerchantOnboardingBrandImages(urls:["https://fixtures.example/a"]);m.draft.brandImages=try .init(urls:["https://fixtures.example/b"])
        m.removeBrandImage(at:0,expected:old);XCTAssertEqual(m.draft.brandImages?.urls,["https://fixtures.example/b"]);XCTAssertEqual(s.uploads,0)
    }
    func testRemoveLastImageRetainsExplicitEmptyField() async throws {
        let(m,s)=try await ready();m.draft.brandImages=try .init(urls:["https://fixtures.example/a"]);m.removeBrandImage(at:0,expected:m.draft.brandImages)
        XCTAssertEqual(m.draft.brandImages?.wireValue,"");XCTAssertEqual(s.uploads,0)
    }
    func testPendingPhotoBlocksNextAndFrozenSubmission() async throws {
        let(m,s)=try await ready();m.step=3;try await select(m);m.next();m.prepare();XCTAssertEqual(m.step,3);XCTAssertNil(m.confirmation);XCTAssertTrue(s.drafts.isEmpty)
    }
    func testFrozenReviewAndExistingSubmissionContainBrandImages() async throws {
        let(m,s)=try await ready();try await select(m);try await upload(m);m.prepare();let review=try XCTUnwrap(m.confirmation)
        XCTAssertEqual(review.draft.brandImages,m.draft.brandImages);await m.coordinator.confirm(review);XCTAssertEqual(s.drafts.first?.brandImages,review.draft.brandImages)
    }
    func testSelectionCancelledByResetDoesNotAttachToNewDraft() async throws {
        let(m,s)=try await ready();let image=try image();var waiter:CheckedContinuation<Void,Never>?
        let task=Task{await m.selectBrandImage(load:{await withCheckedContinuation{waiter=$0};return image})};while waiter==nil{await Task.yield()}
        m.reset();waiter?.resume();await task.value;XCTAssertNil(m.selectedBrandImage);XCTAssertEqual(s.uploads,0)
    }
    func testAccountChangeDuringUploadDoesNotAttachLateURL() async throws {
        let(m,s)=try await ready();try await select(m);let id=try XCTUnwrap(m.selectedBrandImageID);s.holdUpload=true
        let task=Task{await m.uploadSelectedBrandImage(expectedID:id)};while s.waiter==nil{await Task.yield()}
        s.identity = .init(accountID:42,epoch:2);s.resume();await task.value;XCTAssertNil(m.draft.brandImages);XCTAssertEqual(s.uploads,1)
    }
    func testFrozenSubmissionBlocksFurtherSelection() async throws {
        let(m,s)=try await ready();m.prepare();XCTAssertNotNil(m.confirmation);try await select(m)
        XCTAssertNil(m.selectedBrandImage);XCTAssertFalse(m.canAddBrandImage);XCTAssertEqual(s.uploads,0)
    }

}
