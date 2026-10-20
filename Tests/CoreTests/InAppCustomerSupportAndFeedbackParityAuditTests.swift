import XCTest
@testable import QuestifyCore

final class InAppCustomerSupportAndFeedbackParityAuditTests: XCTestCase {
    func testCanonicalSupportChannelsPassParityAudit() {
        let channels = InAppCustomerSupportAndFeedbackParityAudit.canonicalChannels
        XCTAssertEqual(channels.count, 4)
        XCTAssertEqual(
            channels.map(\.id),
            [
                "profile-general-feedback",
                "order-after-sales-and-refund-support",
                "ugc-and-safety-report-followup",
                "merchant-and-club-settlement-inquiry"
            ]
        )

        let evaluation = InAppCustomerSupportAndFeedbackParityAudit.evaluate(channels: channels)
        XCTAssertEqual(evaluation.totalChannels, 4)
        XCTAssertEqual(evaluation.compliantChannels, 4)
        XCTAssertTrue(evaluation.isSupportParityReady)
    }

    func testUnredactedDiagnosticsBeforeAttachmentFailsChannelCompliance() {
        var channels = InAppCustomerSupportAndFeedbackParityAudit.canonicalChannels
        channels[0] = CustomerSupportChannelDescriptor(
            id: "profile-general-feedback",
            channelName: "Profile General Feedback & Bug Report",
            supportsOfflineDraftPreservation: true,
            redactsDiagnosticsBeforeAttachment: false,
            providesExpectedResponseSLAHint: true
        )

        XCTAssertFalse(channels[0].isCompliant)
        let evaluation = InAppCustomerSupportAndFeedbackParityAudit.evaluate(channels: channels)
        XCTAssertEqual(evaluation.totalChannels, 4)
        XCTAssertEqual(evaluation.compliantChannels, 3)
        XCTAssertFalse(evaluation.isSupportParityReady)
    }

    func testMissingOfflineDraftPreservationIsDetected() {
        var channels = InAppCustomerSupportAndFeedbackParityAudit.canonicalChannels
        channels[1] = CustomerSupportChannelDescriptor(
            id: "order-after-sales-and-refund-support",
            channelName: "Order After-Sales & Refund Support",
            supportsOfflineDraftPreservation: false,
            redactsDiagnosticsBeforeAttachment: true,
            providesExpectedResponseSLAHint: true
        )

        XCTAssertFalse(channels[1].isCompliant)
        let evaluation = InAppCustomerSupportAndFeedbackParityAudit.evaluate(channels: channels)
        XCTAssertEqual(evaluation.totalChannels, 4)
        XCTAssertEqual(evaluation.compliantChannels, 3)
        XCTAssertFalse(evaluation.isSupportParityReady)
    }

    func testMissingExpectedResponseSLAHintIsDetected() {
        var channels = InAppCustomerSupportAndFeedbackParityAudit.canonicalChannels
        channels[3] = CustomerSupportChannelDescriptor(
            id: "merchant-and-club-settlement-inquiry",
            channelName: "Merchant & Club Settlement Inquiry",
            supportsOfflineDraftPreservation: true,
            redactsDiagnosticsBeforeAttachment: true,
            providesExpectedResponseSLAHint: false
        )

        XCTAssertFalse(channels[3].isCompliant)
        let evaluation = InAppCustomerSupportAndFeedbackParityAudit.evaluate(channels: channels)
        XCTAssertEqual(evaluation.totalChannels, 4)
        XCTAssertEqual(evaluation.compliantChannels, 3)
        XCTAssertFalse(evaluation.isSupportParityReady)
    }
}
