import XCTest
@testable import QuestifyCore

final class AttachmentReviewProducerTests: XCTestCase {
    func testFirstJourneySixteenTypesVisibleProjectionIsNotApprovalRecoverOriginal() throws {
        XCTAssertEqual(AttachmentReviewProducer.typeCount(), 16)
        XCTAssertEqual(AttachmentType.allCases.map(\.rawValue), [
            "IMAGE", "VIDEO", "AUDIO", "FILE", "LOCATION", "STICKER", "LINK", "CARD",
            "POLL", "CONTACT", "VOICE_NOTE", "LIVE", "MUSIC", "GIF", "ALBUM", "MINI_PROGRAM"
        ])
        var producer = AttachmentReviewProducer()
        var index = 0
        for type in AttachmentType.allCases {
            index += 1
            let requestId = "att-\(index)"
            let pending = try producer.submit(
                originalRequestID: requestId, type: type, originalDigest: "digest-" + type.rawValue)
            XCTAssertEqual(pending.status, AttachmentReviewProducer.statusPending)
            let recovered = try producer.recover(originalRequestID: requestId, appliedProjectionStatus: "VISIBLE")
            XCTAssertEqual(recovered.status, AttachmentReviewProducer.statusPending)
            XCTAssertTrue(recovered.currentProjectionClaimsVisible)
            XCTAssertTrue(recovered.originalIsNotVisibleProjection())
            XCTAssertFalse(producer.treatsVisibleProjectionAsApproval(ImmutableReceiptProducer.projectionApplied))
            XCTAssertEqual(try producer.decide(
                originalRequestID: requestId, decision: AttachmentReviewProducer.statusApproved).status,
                           AttachmentReviewProducer.statusApproved)
            XCTAssertEqual(producer.recoverOriginal(
                originalRequestID: requestId,
                appliedProjectionStatus: ImmutableReceiptProducer.projectionApplied).type, type)
        }
        XCTAssertEqual(index, 16)
        let unknown = producer.recoverUnknown(
            originalRequestID: "att-missing", appliedProjectionStatus: "VISIBLE")
        XCTAssertEqual(unknown.status, AttachmentReviewProducer.statusUnknown)
        XCTAssertEqual(unknown.mintedNewRequest, false)
        XCTAssertTrue(unknown.jsonObject()["usedVisibleProjectionAsApproval"] as? Bool == false)
    }

    func testDuplicateSameFingerprintReturnsOriginalAndConflictThrows() throws {
        var producer = AttachmentReviewProducer()
        let first = try producer.submit(originalRequestID: "att-dup", type: .image, originalDigest: "digest-IMAGE")
        let replay = try producer.submit(originalRequestID: "att-dup", type: .image, originalDigest: "digest-IMAGE")
        XCTAssertEqual(first.originalDigest, replay.originalDigest)
        XCTAssertThrowsError(try producer.submit(
            originalRequestID: "att-dup", type: .video, originalDigest: "digest-IMAGE")) { error in
            XCTAssertEqual(error as? NotifyFailure, .attachmentConflict(requestId: "att-dup"))
        }
        XCTAssertNil(ImmutableReceiptProducer.parse(""))
        XCTAssertTrue(try producer.recover(originalRequestID: "att-dup", appliedProjectionStatus: "VISIBLE")
            .jsonObject()["requestId"] is String)
    }

    func testRecoverOriginalOfNeverSeenIdDoesNotOccupyThenUniqueSubmitApplies() throws {
        var producer = AttachmentReviewProducer()
        let blank = producer.recoverOriginal(originalRequestID: "  ", appliedProjectionStatus: nil)
        XCTAssertNil(blank.requestId)
        XCTAssertEqual(blank.status, AttachmentReviewProducer.statusUnknown)
        XCTAssertTrue(producer.originalByRequestID.isEmpty)
        let recovered = producer.recoverOriginal(
            originalRequestID: "att-recover-never-c09", appliedProjectionStatus: "VISIBLE")
        XCTAssertEqual(recovered.requestId, "att-recover-never-c09")
        XCTAssertEqual(recovered.status, AttachmentReviewProducer.statusUnknown)
        XCTAssertEqual(recovered.mintedNewRequest, false)
        XCTAssertNil(producer.originalByRequestID["att-recover-never-c09"])
        XCTAssertTrue(producer.originalByRequestID.isEmpty)
        let first = try producer.submit(
            originalRequestID: "att-recover-never-c09", type: .image, originalDigest: "digest-IMAGE")
        XCTAssertEqual(first.requestId, "att-recover-never-c09")
        XCTAssertEqual(first.status, AttachmentReviewProducer.statusPending)
        XCTAssertEqual(producer.originalByRequestID.count, 1)
        let replay = producer.recoverOriginal(
            originalRequestID: "att-recover-never-c09", appliedProjectionStatus: "VISIBLE")
        XCTAssertEqual(replay.status, AttachmentReviewProducer.statusPending)
        XCTAssertEqual(replay.requestId, "att-recover-never-c09")
        XCTAssertEqual(producer.originalByRequestID.count, 1)
    }

    func testUnusedDecideOfNeverSeenDoesNotOccupyThenUniqueSubmitApplies() throws {
        var producer = AttachmentReviewProducer()
        XCTAssertThrowsError(try producer.decide(
            originalRequestID: "att-decide-never-c09",
            decision: AttachmentReviewProducer.statusApproved)) { error in
            XCTAssertEqual(error as? NotifyFailure, .originalMissing("att-decide-never-c09"))
        }
        XCTAssertTrue(producer.originalByRequestID.isEmpty, "未见附件 decide 观察不得占账")
        XCTAssertNil(producer.originalByRequestID["att-decide-never-c09"])
        let unused = producer.recoverOriginal(
            originalRequestID: "att-decide-never-c09", appliedProjectionStatus: "VISIBLE")
        XCTAssertEqual(unused.requestId, "att-decide-never-c09")
        XCTAssertEqual(unused.status, AttachmentReviewProducer.statusUnknown)
        XCTAssertTrue(producer.originalByRequestID.isEmpty)
        let first = try producer.submit(
            originalRequestID: "att-decide-never-c09", type: .image, originalDigest: "digest-IMAGE")
        XCTAssertEqual(first.requestId, "att-decide-never-c09")
        XCTAssertEqual(first.status, AttachmentReviewProducer.statusPending)
        XCTAssertEqual(producer.originalByRequestID.count, 1)
        XCTAssertEqual(producer.recoverOriginal(
            originalRequestID: "att-decide-never-c09", appliedProjectionStatus: "VISIBLE").status,
                       AttachmentReviewProducer.statusPending)
        XCTAssertEqual(producer.originalByRequestID.count, 1)
    }
}
