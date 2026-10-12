import XCTest
import SwiftUI
@testable import Questify

@MainActor final class ProfileComplaintPreparationAppTests: XCTestCase {
    func testFixtureReadsOnlyServerSelectorShape() async throws {
        let r = ProfileComplaintPreparationFixtureReader(scenario: "content")
        let topics = try ProfileComplaintTopic.decode(await r.read(.complaintTopics))
        XCTAssertEqual(topics.map(\.id), [71, 72]); XCTAssertEqual(r.calls, 1)
    }
    func testFixtureHasNoUnrelatedReads() async {
        let r = ProfileComplaintPreparationFixtureReader(scenario: "content")
        do { _ = try await r.read(.finance); XCTFail("unexpected read") } catch { XCTAssertEqual(r.calls, 0) }
    }
    func testFailureCanRetry() async {
        let r = ProfileComplaintPreparationFixtureReader(scenario: "failure")
        let m = ProfileComplaintPreparationController(reader: r, isCurrent: { true }); await m.load(); XCTAssertEqual(m.issue, .failed)
        await m.load(); XCTAssertEqual(m.topics?.count, 2); XCTAssertNil(m.issue)
    }
    func testEmptyFixtureIsNotFailure() async {
        let r = ProfileComplaintPreparationFixtureReader(scenario: "empty")
        let m = ProfileComplaintPreparationController(reader: r, isCurrent: { true }); await m.load(); XCTAssertEqual(m.topics, []); XCTAssertNil(m.issue)
    }
    func testReviewIncludesOptionalFieldsAndReturnsUnchanged() async {
        let r = ProfileComplaintPreparationFixtureReader(scenario: "content")
        let m = ProfileComplaintPreparationController(reader: r, isCurrent: { true }); await m.load()
        m.change { $0.topicID = 71; $0.kind = .service; $0.reason = "Synthetic issue"; $0.contact = "synthetic contact" }
        XCTAssertTrue(m.beginReview()); XCTAssertEqual(m.review?.reason, "【服务与履约】Synthetic issue\n联系方式：synthetic contact")
        m.continueEditing(); XCTAssertEqual(m.draft.contact, "synthetic contact"); XCTAssertEqual(r.calls, 1)
    }
    func testMalformedSelectionNeverShowsEditor() async {
        let r = ProfileComplaintPreparationFixtureReader(scenario: "malformed")
        let m = ProfileComplaintPreparationController(reader: r, isCurrent: { true }); await m.load()
        XCTAssertNil(m.topics); XCTAssertFalse(m.canEdit); XCTAssertEqual(m.issue, .failed)
    }
    func testSignedOutFixtureNeverReads() async {
        let r = ProfileComplaintPreparationFixtureReader(scenario: "guest")
        let m = ProfileComplaintPreparationController(reader: r, isCurrent: { true }); await m.load(); XCTAssertEqual(r.calls, 0)
    }
    func testNativeViewUsesRealComponentWithNoWriterArgument() {
        let r = ProfileComplaintPreparationFixtureReader(scenario: "content")
        _ = UIHostingController(rootView: ProfileComplaintPreparationView(reader: r, isCurrent: { true }))
        XCTAssertEqual(r.calls, 0)
    }
}
