import XCTest
@testable import QuestifyCore

final class ProjectTopicMediaUploadPlanTests: XCTestCase {
    private func facts(_ kind: ProjectTopicMediaKind, _ fill: Character) -> ProjectTopicMediaFacts {
        .init(reference: .init(id: UUID(), revision: UUID()), kind: kind, mimeType: kind == .image ? "image/jpeg" : "video/mp4",
              byteCount: 10, width: 4, height: 3, durationMilliseconds: kind == .video ? 1000 : nil,
              contentSHA256: String(repeating: fill, count: 64))
    }

    func testRemoteStagesAreNeverReportedAsAvailable() {
        XCTAssertEqual(ProjectTopicMediaStage.allCases.count, 8)
        XCTAssertEqual(ProjectTopicMediaUploadPlan.status(of: .selection), .localOnly)
        XCTAssertEqual(ProjectTopicMediaUploadPlan.status(of: .upload), .disabled)
        for stage in [ProjectTopicMediaStage.moderation, .save, .read, .playback] {
            XCTAssertEqual(ProjectTopicMediaUploadPlan.status(of: stage), .noContract)
        }
    }

    func testRequestIDIsStableAcrossLocalReferencesAndBoundToDraft() throws {
        let topic = try ProjectEditDraftIdentity(topicID: 9)
        let a = ProjectTopicMediaUploadPlan.request(for: [facts(.image, "a"), facts(.video, "b")], identity: topic)
        let b = ProjectTopicMediaUploadPlan.request(for: [facts(.image, "a"), facts(.video, "b")], identity: topic)
        XCTAssertEqual(a?.requestID, b?.requestID)
        XCTAssertEqual(a?.kinds, [.image, .video])
        let other = ProjectTopicMediaUploadPlan.request(for: [facts(.image, "a"), facts(.video, "b")], identity: try ProjectEditDraftIdentity(topicID: 10))
        XCTAssertNotEqual(a?.requestID, other?.requestID)
        XCTAssertNil(ProjectTopicMediaUploadPlan.request(for: [], identity: topic))
        XCTAssertNil(ProjectTopicMediaUploadPlan.request(for: [facts(.image, "Z")], identity: topic))
    }

    func testDefaultPlanBlocksOnEmptyAllowlist() throws {
        let request = ProjectTopicMediaUploadPlan.request(for: [facts(.video, "c")], identity: try ProjectEditDraftIdentity(topicID: 1))
        XCTAssertEqual(ProjectTopicMediaUploadPlan().block(for: request), .noReviewedEndpoint)
        XCTAssertEqual(ProjectTopicMediaUploadPlan().block(for: nil), .emptySelection)
        XCTAssertEqual(ProjectTopicMediaUploadPlan(approvedUploadPath: "fixture/upload").block(for: request), .disabledByConfiguration)
        XCTAssertNil(ProjectTopicMediaUploadPlan(approvedUploadPath: "fixture/upload", uploadEnabled: true).block(for: request))
    }

    func testUncertainOutcomeRequiresMatchingReadback() throws {
        let request = try XCTUnwrap(ProjectTopicMediaUploadPlan.request(for: [facts(.image, "d")], identity: try ProjectEditDraftIdentity(topicID: 2)))
        var plan = ProjectTopicMediaUploadPlan(approvedUploadPath: "fixture/upload", uploadEnabled: true)
        plan.markUncertain(request)
        XCTAssertEqual(plan.block(for: request), .awaitingReadback)
        plan.resolveReadback(requestID: "topic-media-other")
        XCTAssertEqual(plan.block(for: request), .awaitingReadback)
        plan.resolveReadback(requestID: request.requestID)
        XCTAssertNil(plan.block(for: request))
    }
}
