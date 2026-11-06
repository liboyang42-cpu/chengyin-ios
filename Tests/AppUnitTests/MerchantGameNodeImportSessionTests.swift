import XCTest
@testable import Questify

@MainActor final class MerchantGameNodeImportSessionTests: XCTestCase {
    func testPreviewDoesNotReturnUntilExplicitAcceptanceAndDismissal() throws {
        let model = MerchantGameNodeImportController()
        model.open { true }
        let session = try XCTUnwrap(model.session)
        session.update("300"); session.preview()
        XCTAssertEqual(session.code?.submissionID, "300")
        XCTAssertEqual(session.raw, "")
        model.accept(session)
        XCTAssertEqual(model.finishDismissal(id: session.id), "300")
        XCTAssertNil(model.finishDismissal(id: session.id))
    }
    func testPreviewThenDismissWithoutAcceptanceDoesNotStage() throws {
        let model = MerchantGameNodeImportController(); model.open { true }
        let session = try XCTUnwrap(model.session)
        session.update("300"); session.preview()
        model.presentationBinding().wrappedValue = false
        XCTAssertNil(model.finishDismissal(id: session.id))
    }
    func testOwnerChangesBetweenAcceptanceAndDismissalRejectsIdentifier() throws {
        var current = true
        let model = MerchantGameNodeImportController(); model.open { current }
        let session = try XCTUnwrap(model.session)
        session.update("300"); session.preview(); model.accept(session)
        current = false
        XCTAssertNil(model.finishDismissal(id: session.id))
    }
    func testRetirementCannotReviveWhenIdentityReturns() throws {
        let model = MerchantGameNodeImportController(); model.open { true }
        let session = try XCTUnwrap(model.session)
        session.update("300"); session.preview(); model.accept(session)
        model.invalidate()
        XCTAssertNil(model.finishDismissal(id: session.id))
        XCTAssertFalse(session.isCurrent); XCTAssertEqual(session.raw, ""); XCTAssertNil(session.code)
    }
    func testAmbiguousAndOversizedInputsNeverStageTruncatedPrefix() throws {
        for raw in ["?submissionId=300&submissionId=301", "{\"submissionId\":300,\"submissionId\":301}",
                    "300" + String(repeating: " ", count: 4096), "https://example.com/?submissionId=300"] {
            let model = MerchantGameNodeImportController(); model.open { true }
            let session = try XCTUnwrap(model.session)
            session.update(raw); session.preview(); model.accept(session)
            XCTAssertNil(session.code); XCTAssertNil(model.finishDismissal(id: session.id))
        }
    }
    func testPendingDismissalBlocksSecondOpenAndOldCallbacksCannotDismissNewSession() throws {
        let model = MerchantGameNodeImportController(); model.open { true }
        let old = try XCTUnwrap(model.session), binding = model.presentationBinding()
        old.update("300"); old.preview(); model.accept(old)
        model.open { true }; XCTAssertTrue(model.session === old)
        XCTAssertEqual(model.finishDismissal(id: old.id), "300")
        model.open { true }; let next = try XCTUnwrap(model.session)
        model.cancel(old); binding.wrappedValue = false; model.accept(old)
        XCTAssertNil(model.finishDismissal(id: old.id))
        XCTAssertTrue(model.session === next)
        XCTAssertTrue(model.presentationBinding().wrappedValue)
    }
    func testUnavailableOwnerCannotOpenOrPreview() throws {
        let model = MerchantGameNodeImportController(); model.open { false }
        XCTAssertNil(model.session)
        var current = true
        model.open { current }; let session = try XCTUnwrap(model.session)
        session.update("300"); current = false; session.preview()
        XCTAssertNil(session.code); XCTAssertEqual(session.raw, "")
    }
}
