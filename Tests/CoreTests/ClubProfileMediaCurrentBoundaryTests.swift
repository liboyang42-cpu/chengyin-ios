import Foundation
import XCTest
@testable import QuestifyCore

@MainActor final class ClubProfileMediaCurrentBoundaryTests: XCTestCase {
    func testBareReferenceCannotBecomeUploadProof() throws {
        var draft = ClubOperationsDraft()
        XCTAssertNoThrow(try draft.validateMedia(original: nil))
        draft.logo = "https://example.test/logo.jpg"
        XCTAssertNil(draft.logoUpload)
        XCTAssertThrowsError(try draft.validateMedia(original: nil))
        draft.discardMedia(.logo, original: nil)
        XCTAssertEqual(draft.logo, "")
        XCTAssertNil(draft.logoUpload)
        XCTAssertNoThrow(try draft.validateMedia(original: nil))
    }
    func testExactOriginalFieldAspectRatios() throws {
        let bytes = Data([255, 216, 255, 0]) // Synthetic envelope only, not decoded or uploaded.
        let square = try RetainedSelectedImage(jpeg: bytes, width: 100, height: 100)
        let cover = try RetainedSelectedImage(jpeg: bytes, width: 160, height: 90)
        XCTAssertTrue(ClubProfileMediaField.logo.accepts(square))
        XCTAssertFalse(ClubProfileMediaField.cover.accepts(square))
        XCTAssertTrue(ClubProfileMediaField.cover.accepts(cover))
        XCTAssertFalse(ClubProfileMediaField.logo.accepts(cover))
    }
    func testOrdinarySessionHasNoMediaServiceOrPermission() {
        let access = ClubOperationsSessionAccess(service: nil, currentSession: { nil })
        XCTAssertNil(access.profileMedia)
        XCTAssertNil(access.welcomeNote)
        let flow = ClubProfileMediaFlow()
        XCTAssertFalse(flow.current)
        flow.retire()
        XCTAssertNil(flow.preview)
        XCTAssertNil(flow.scope)
        XCTAssertNil(flow.service)
    }
}
