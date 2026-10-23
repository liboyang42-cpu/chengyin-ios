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
}
