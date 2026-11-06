import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class ProjectCloudDraftReceiptPresentationTests: XCTestCase {
    func testOriginalIntentsHaveDistinctLabelsWithoutChangingTheirWireMeaning() {
        XCTAssertEqual(ProjectCloudDraftReceiptPresentation.intentKey(.ordinary), "intent.ordinary")
        XCTAssertEqual(ProjectCloudDraftReceiptPresentation.intentKey(.saveCloudDraft), "intent.save")
        XCTAssertEqual(ProjectCloudDraftReceiptPresentation.intentKey(.submitServerDraft), "intent.submit")
        XCTAssertNil(ProjectCloudDraftReceiptPresentation.explanationKey(.ordinary))
        XCTAssertEqual(ProjectCloudDraftReceiptPresentation.explanationKey(.saveCloudDraft), "intent.saveExplanation")
        XCTAssertEqual(ProjectCloudDraftReceiptPresentation.explanationKey(.submitServerDraft), "intent.submitExplanation")
        XCTAssertEqual(ProjectEditSubmissionIntent.from(payload: ["saveDraft": .number(1)]), .saveCloudDraft)
        XCTAssertEqual(ProjectEditSubmissionIntent.from(payload: ["saveDraft": .number(0)]), .submitServerDraft)
        XCTAssertEqual(ProjectEditSubmissionIntent.from(payload: [:]), .ordinary)
    }

    func testEveryOriginalProcessingCodeHasAnExplicitTranslation() {
        let codes = ["PENDING", "FAILED", "NOT_REQUIRED", "DEFERRED_DRAFT", "RECORDED", "STALE_SOURCE",
            "SUPERSEDED", "AWAITING_NEW_RECORD", "RECORDED_DECISION", "WAITING", "PROCESSING", "DONE",
            "RETRYABLE_CALLBACK", "IGNORED_STALE", "MANUAL_REVIEW", "NOT_CONFIGURED", "REGISTERED",
            "WRITER_BUNDLE_SUBMISSION", "SPOT_CHECK_REUSED", "SPOT_CHECK_CREATED", "APPROVE", "REJECT",
            "REVERT", "CANCEL", "ESCALATE"]
        XCTAssertEqual(Set(ProjectCloudDraftReceiptPresentation.statusKeys.keys), Set(codes))
        for code in codes { XCTAssertNotEqual(ProjectCloudDraftReceiptPresentation.statusKey(code), "status.unknown", code) }
        XCTAssertEqual(ProjectCloudDraftReceiptPresentation.statusKey("WAITING"), ProjectCloudDraftReceiptPresentation.statusKey("PROCESSING"))
        XCTAssertNotEqual(ProjectCloudDraftReceiptPresentation.statusKey("FAILED"), ProjectCloudDraftReceiptPresentation.statusKey("DONE"))
        XCTAssertNotEqual(ProjectCloudDraftReceiptPresentation.statusKey("DEFERRED_DRAFT"), ProjectCloudDraftReceiptPresentation.statusKey("APPROVE"))
        XCTAssertNotEqual(ProjectCloudDraftReceiptPresentation.statusKey("SPOT_CHECK_REUSED"), ProjectCloudDraftReceiptPresentation.statusKey("SPOT_CHECK_CREATED"))
    }

    func testUnknownCodesAreNeverNormalizedIntoSuccessOrApproval() {
        for code in ["", "approved", "done", "APPROVE ", "NEW_SERVER_STATE", "已通过"] {
            XCTAssertEqual(ProjectCloudDraftReceiptPresentation.statusKey(code), "status.unknown")
        }
    }

    func testUnavailableReceiptIsNotAnAuthoritativeEmptyReceipt() throws {
        XCTAssertEqual(ProjectCloudDraftReceiptPresentation.processing(nil), .unavailable)
        let empty = try receipt(audits: [], media: [])
        XCTAssertEqual(ProjectCloudDraftReceiptPresentation.processing(empty), .recorded(empty))
        XCTAssertNotEqual(ProjectCloudDraftReceiptPresentation.processing(empty), .unavailable)
        XCTAssertTrue(empty.audits.isEmpty)
        XCTAssertTrue(empty.media.isEmpty)
    }

    func testMissingRiskIsNeitherClearNorMatched() {
        XCTAssertEqual(ProjectCloudDraftReceiptPresentation.riskKey(nil), "risk.unknown")
        XCTAssertEqual(ProjectCloudDraftReceiptPresentation.riskKey(false), "risk.notMatched")
        XCTAssertEqual(ProjectCloudDraftReceiptPresentation.riskKey(true), "risk.matched")
    }

    func testRenderingProjectionRetainsExactRequestFactsAndDoesNotInventResumePermission() throws {
        for allowed in [false, true] {
            let original = try receipt(canResume: allowed)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let before = try encoder.encode(original)
            guard case .recorded(let projected) = ProjectCloudDraftReceiptPresentation.processing(original) else {
                return XCTFail("A real supplied receipt must stay distinct from unavailable")
            }
            XCTAssertEqual(try encoder.encode(projected), before)
            XCTAssertEqual(projected.canResume, allowed)
            XCTAssertEqual(projected.requestID, original.requestID)
            XCTAssertEqual(projected.payloadSHA256, original.payloadSHA256)
            XCTAssertEqual(projected.audits.first?.actions, ["APPROVE", "REVERT"])
            XCTAssertEqual(projected.media.map(\.risky), [nil, false, true])
        }
    }

    func testLegacyCoreDisplayLabelsRemainCompatible() {
        XCTAssertEqual(ProjectEditSubmissionIntent.saveCloudDraft.label, "确认保存云草稿（不发布）")
        XCTAssertEqual(ProjectEditPostProcessingReceipt.label("DEFERRED_DRAFT"), "草稿仅保留标记，未公开提审")
        XCTAssertEqual(ProjectEditPostProcessingReceipt.label("UNRECOGNIZED"), "状态暂不能确定，未重复发送")
    }

    func testEveryShippingLabelHasEnglishAndSimplifiedChinese() throws {
        let keys = Set(ProjectCloudDraftReceiptPresentation.statusKeys.values).union([
            "status.unknown", "intent.ordinary", "intent.save", "intent.submit", "intent.saveExplanation", "intent.submitExplanation",
            "cloud.title", "cloud.savedFact", "cloud.projectID", "cloud.openProjects", "cloud.returnHint",
            "action.saveCloud", "action.submitDraft", "action.refreshProcessing", "action.resumeProcessing",
            "processing.title", "processing.savedFact", "processing.unavailable", "processing.spotCheck", "processing.auditID",
            "processing.association", "processing.auditState", "processing.actions", "processing.noActions", "processing.noAudits",
            "processing.noMedia", "processing.mediaID", "processing.mediaState", "processing.creative",
            "risk.matched", "risk.notMatched", "risk.unknown"
        ])
        for language in ["en", "zh-Hans"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            for key in keys {
                let value = bundle.localizedString(forKey: key, value: "MISSING", table: "ProjectCloudDraftReceipt")
                XCTAssertNotEqual(value, "MISSING", "\(language): \(key)")
                XCTAssertFalse(value.isEmpty)
            }
        }
    }

    func testNativeFactsCanMountUnavailableEmptyAndRecordedAtAccessibilitySize() throws {
        // Rendering preparation only: this is not screenshot, VoiceOver or live-writer verification.
        let receipts: [ProjectEditPostProcessingReceipt?] = [nil, try receipt(audits: [], media: []), try receipt()]
        for value in receipts {
            for language in ["en", "zh-Hans"] {
                let host = UIHostingController(rootView: Form {
                    ProjectCloudDraftIntentSummary(intent: .saveCloudDraft)
                    ProjectCloudDraftProcessingFacts(receipt: value)
                }.environment(\.locale, Locale(identifier: language))
                    .environment(\.dynamicTypeSize, .accessibility5))
                host.loadViewIfNeeded(); host.view.layoutIfNeeded()
                XCTAssertNotNil(host.view)
            }
        }
    }

    /// Dedicated presentation input only; these bytes do not authorize an operation.
    private func receipt(canResume: Bool = false, audits: [[String: Any]]? = nil,
                         media: [[String: Any]]? = nil) throws -> ProjectEditPostProcessingReceipt {
        let values: [String: Any] = [
            "protocolVersion": "original-project-postprocess-v1",
            "requestID": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            "payloadSHA256": String(repeating: "a", count: 64),
            "spotCheckState": "DEFERRED_DRAFT",
            "audits": audits ?? [["taskID": 42, "association": "WRITER_BUNDLE_SUBMISSION",
                "submissionRecordID": 9, "snapshotSHA256": String(repeating: "b", count: 64),
                "state": "RECORDED_DECISION", "actions": ["APPROVE", "REVERT"]]],
            "media": media ?? [
                ["mediaSHA256": "first-media", "state": "WAITING"],
                ["mediaSHA256": "second-media", "state": "DONE", "risky": false],
                ["mediaSHA256": "third-media", "state": "MANUAL_REVIEW", "risky": true]],
            "creativeState": "NOT_REQUIRED", "canResume": canResume
        ]
        return try JSONDecoder().decode(ProjectEditPostProcessingReceipt.self, from: JSONSerialization.data(withJSONObject: values))
    }
}
