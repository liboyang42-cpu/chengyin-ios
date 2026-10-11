import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private func timelineTemplate(_ json: String? = nil, text: String? = "Original story") -> MerchantNodeTemplate {
    var value = MerchantNodeTemplate(); value.id = 71; value.title = "Timeline"; value.method = .photo
    value.storyTimeline = .init(storyText: text, storyJSON: json); return value
}

final class MerchantTemplateStoryTimelineContractTests: XCTestCase {
    func testMissingNullAndMalformedOuterFields() throws {
        for raw in ["{}", #"{"storyText":null,"storyJson":null}"#] {
            let value = try JSONDecoder().decode(MerchantNodeTemplate.self, from: Data(raw.utf8))
            XCTAssertEqual(value.storyTimeline, MerchantTemplateStoryTimeline()); XCTAssertTrue(value.storyTimeline.fields.isEmpty)
        }
        for raw in [#"{"storyText":42}"#, #"{"storyJson":[]}"#, #"{"storyJson":true}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(MerchantNodeTemplate.self, from: Data(raw.utf8)))
        }
    }
    func testLegacyTextStaysRawUntilExplicitEditCreatesTimeline() throws {
        var value = MerchantTemplateStoryTimeline(storyText: "  Old full story  ")
        XCTAssertEqual(value.fields, ["storyText": "  Old full story  "]); XCTAssertTrue(value.enabled)
        value.update(1, tag: "Morning")
        let nodes = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(XCTUnwrap(value.fields["storyJson"]).utf8)) as? [[String: Any]])
        XCTAssertEqual(nodes.first?["text"] as? String, "  Old full story  ")
        XCTAssertEqual(nodes.first?["tag"] as? String, "Morning"); XCTAssertEqual(value.fields["storyText"], "Old full story")
    }
    func testEmptyArrayFallsBackToLegacyTextWithoutDroppingItOnRead() {
        let value = MerchantTemplateStoryTimeline(storyText: "Legacy", storyJSON: "[]")
        XCTAssertTrue(value.isEditable); XCTAssertEqual(value.beats.first?.text, "Legacy")
        XCTAssertEqual(value.fields["storyJson"], "[]"); XCTAssertFalse(value.isEdited)
    }
    func testAddMoveRemoveUseStableLocalIDsAndKeepLastRow() {
        var value = MerchantTemplateStoryTimeline(); value.setEnabled(true)
        value.update(1, text: "First"); value.add(); value.update(2, text: "Second")
        value.move(2, offset: -1); XCTAssertEqual(value.beats.map(\.id), [2, 1])
        XCTAssertEqual(value.previewBeats.map(\.text), ["Second", "First"])
        value.remove(1); value.remove(2); XCTAssertEqual(value.beats.map(\.id), [2])
        value.add(); XCTAssertEqual(value.beats.map(\.id), [2, 3])
    }
    func testKnownModernAndLegacyImagesSurviveTextAndOrderEdits() throws {
        let raw = #"[{"text":"A","tag":"Dawn","imgs":["/a.jpg"],"img":"/legacy.jpg"},{"text":"B","img":"/b.jpg"}]"#
        var value = MerchantTemplateStoryTimeline(storyJSON: raw)
        XCTAssertEqual(value.fields["storyJson"], raw); XCTAssertEqual(value.beats[0].imageReferenceCount, 2)
        value.update(1, text: "Changed"); value.move(2, offset: -1)
        let nodes = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(XCTUnwrap(value.fields["storyJson"]).utf8)) as? [[String: Any]])
        XCTAssertEqual(nodes[0]["img"] as? String, "/b.jpg")
        XCTAssertEqual(nodes[1]["imgs"] as? [String], ["/a.jpg"]); XCTAssertEqual(nodes[1]["img"] as? String, "/legacy.jpg")
        XCTAssertEqual(value.removedImageCount, 0); XCTAssertNil(nodes[0]["id"])
    }
    func testImageOnlyMomentIsRetainedEvenWhenTextIsBlank() throws {
        var value = MerchantTemplateStoryTimeline(storyJSON: #"[{"text":"","tag":"","imgs":[],"img":"/legacy.jpg"}]"#)
        value.update(1, tag: "Photo moment")
        XCTAssertEqual(value.previewBeats.count, 1); XCTAssertNil(value.blocker)
        XCTAssertEqual(value.fields["storyText"], ""); XCTAssertNotEqual(value.fields["storyJson"], "")
    }
    func testUnknownOrMalformedInnerShapesAreOpaqueAndEveryMutatorIsNoOp() {
        for raw in ["not json", "{}", "[3]", #"[{"text":2}]"#, #"[{"imgs":[false]}]"#, #"[{"text":"A","future":{"private":true}}]"#] {
            var value = MerchantTemplateStoryTimeline(storyText: "Legacy summary", storyJSON: raw); let original = value
            XCTAssertFalse(value.isEditable); value.setEnabled(false); value.add(); value.remove(1); value.move(1, offset: 1); value.update(1, text: "No")
            XCTAssertEqual(value, original); XCTAssertEqual(value.fields["storyJson"], raw); XCTAssertEqual(value.fields["storyText"], "Legacy summary")
            XCTAssertNil(value.blocker)
        }
    }
    func testTagOnlyEditedMomentBlocksInsteadOfSilentlyDroppingLabel() {
        var value = timelineTemplate(nil, text: nil); value.storyTimeline.setEnabled(true)
        value.storyTimeline.update(1, tag: "Dawn")
        XCTAssertEqual(value.blocker, "merchant.storyTimeline.tagNeedsContent")
        XCTAssertThrowsError(try MerchantOperationsDraft.template(value).previews())
        value.storyTimeline.update(1, text: "A new day"); XCTAssertNil(value.blocker)
    }
    func testBlankNewMomentsAreOmittedAndDoNotBecomeRuntimeNodes() throws {
        var value = MerchantTemplateStoryTimeline(); value.setEnabled(true); value.add(); value.update(2, text: "Kept")
        let nodes = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(XCTUnwrap(value.fields["storyJson"]).utf8)) as? [[String: Any]])
        XCTAssertEqual(nodes.count, 1); XCTAssertEqual(value.fields["storyText"], "Kept")
    }
    func testProjectionBoundsUTF16WithoutTruncatingFullTimelineOrBreakingEmoji() throws {
        let full = String(repeating: "a", count: 499) + "🧩" + "tail"
        var value = MerchantTemplateStoryTimeline(); value.setEnabled(true); value.update(1, text: full)
        XCTAssertEqual(value.textProjection, String(repeating: "a", count: 499)); XCTAssertTrue(value.projectionIsShortened)
        let nodes = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(XCTUnwrap(value.fields["storyJson"]).utf8)) as? [[String: Any]])
        XCTAssertEqual(nodes[0]["text"] as? String, full)
        value.update(1, text: String(repeating: "🧩", count: 250)); XCTAssertEqual(value.textProjection.utf16.count, 500)
        XCTAssertFalse(value.projectionIsShortened)
    }
    func testDisableClearsBothKeysAndDisclosesRemovedMomentsAndImageReferences() {
        var value = MerchantTemplateStoryTimeline(storyText: "Summary", storyJSON: #"[{"text":"A","imgs":["/a.jpg"]},{"text":"B","img":"/b.jpg"}]"#)
        value.setEnabled(false)
        XCTAssertEqual(value.fields, ["storyText": "", "storyJson": ""]); XCTAssertTrue(value.clearsSource)
        XCTAssertEqual(value.removedImageCount, 2); XCTAssertEqual(value.removedBeats.map(\.text), ["A", "B"])
        value.setEnabled(true); XCTAssertEqual(value.previewBeats.count, 0)
    }
    func testDeletingOneSavedMomentReportsOnlyItsImagesAndText() {
        var value = MerchantTemplateStoryTimeline(storyJSON: #"[{"text":"A","imgs":["/a.jpg"]},{"text":"B","img":"/b.jpg"}]"#)
        value.remove(1)
        XCTAssertEqual(value.removedImageCount, 1); XCTAssertEqual(value.removedBeats.map(\.text), ["A"])
        XCTAssertFalse(value.clearsSource); XCTAssertEqual(value.previewBeats.map(\.text), ["B"])
    }
    func testInvalidIndicesAndUnchangedInputDoNotMakeSourceDirty() {
        var value = MerchantTemplateStoryTimeline(storyText: "Original"); let original = value
        value.update(99, text: "No"); value.update(1, text: "Original"); value.remove(1); value.remove(99)
        value.move(1, offset: -1); value.move(1, offset: 2); value.setEnabled(true)
        XCTAssertEqual(value, original)
    }
    func testExactPreviewPayloadDoesNotInventRuntimeOrMediaFields() throws {
        var value = timelineTemplate(); value.couponID = 19; value.storyTimeline.update(1, text: "Revised")
        let preview = try XCTUnwrap(MerchantOperationsDraft.template(value).previews().first)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: preview.json) as? [String: Any])
        XCTAssertEqual(preview.path, "api/merchant/city-node/template/submit")
        XCTAssertEqual(body["storyText"] as? String, "Revised"); XCTAssertNotNil(body["storyJson"] as? String)
        XCTAssertEqual(body["couponId"] as? Int, 19)
        for key in ["story_json", "beats", "storyEnabled", "storyImg", "rewardRulesJson"] { XCTAssertNil(body[key]) }
    }
    func testAIStoryDoesNotOverwriteTimelineAndLocalPlansStillStopSending() throws {
        var value = timelineTemplate()
        let result = try MerchantTemplateAssistResult(.object(["storyText": .string("AI prose"), "storyJson": .string("[]")]))
        let merged = result.merge(into: value, captured: value, edits: .init(), capturedEdits: .init())
        XCTAssertEqual(merged.storyTimeline, value.storyTimeline)
        var plan = MerchantTemplateExitPlan(); plan.offlineAlternative = "Printed card"; plan.failureExit = "Stop playing"
        value.exitPlan = plan
        XCTAssertThrowsError(try MerchantOperationsDraft.template(value).previews()) {
            XCTAssertEqual($0 as? MerchantOperationsFailure, .liveWritesDisabled)
        }
    }
}

@MainActor final class MerchantTemplateStoryTimelineCoordinatorTests: XCTestCase {
    func testCancelStaleReviewAndDiscardKeepTimelineAndMedia() async throws {
        let reader = MerchantOperationsFixtureReader(); let source = timelineTemplate(#"[{"text":"A","imgs":["/a.jpg"]},{"text":"B"}]"#)
        reader.replace(.template(71), with: .draft(.template(source)))
        let coordinator = MerchantOperationsCoordinator(reader: reader, destination: .template(71))
        await coordinator.load(); var edited = source; edited.storyTimeline.remove(1)
        coordinator.edit(.template(edited)); coordinator.prepare(); let review = try XCTUnwrap(coordinator.confirmation)
        coordinator.cancelConfirmation(); XCTAssertEqual(coordinator.draft, .template(edited))
        edited.storyTimeline.update(2, text: "Changed again"); coordinator.edit(.template(edited))
        if case .template(let frozen) = review.draft { XCTAssertEqual(frozen.storyTimeline.previewBeats[0].text, "B"); XCTAssertEqual(frozen.storyTimeline.removedImageCount, 1) }
        else { XCTFail() }
        await coordinator.confirm(review); XCTAssertEqual(reader.saveCount, 0)
        coordinator.discardChanges(); XCTAssertEqual(coordinator.draft, .template(source))
    }
    func testFixtureClearReadbackConsumesRemovalIntentAndCannotReplay() async throws {
        let reader = MerchantOperationsFixtureReader(); let source = timelineTemplate()
        reader.replace(.template(71), with: .draft(.template(source)))
        let coordinator = MerchantOperationsCoordinator(reader: reader, destination: .template(71))
        await coordinator.load(); var edited = source; edited.storyTimeline.setEnabled(false)
        coordinator.edit(.template(edited)); coordinator.prepare(); let review = try XCTUnwrap(coordinator.confirmation)
        await coordinator.confirm(review)
        guard case .template(let returned) = coordinator.draft else { return XCTFail() }
        XCTAssertEqual(returned.storyTimeline.fields, ["storyText": "", "storyJson": ""])
        XCTAssertFalse(returned.storyTimeline.isEdited); XCTAssertFalse(returned.storyTimeline.enabled)
        XCTAssertTrue(returned.storyTimeline.removedBeats.isEmpty); XCTAssertFalse(coordinator.isDirty)
        await coordinator.confirm(review); XCTAssertEqual(reader.saveCount, 1)
        await coordinator.load(); XCTAssertEqual(coordinator.draft, .template(returned))
    }
    func testAccountSwitchPreventsReviewedStoryFromSaving() async throws {
        let reader = MerchantOperationsFixtureReader(); let source = timelineTemplate()
        reader.replace(.template(71), with: .draft(.template(source)))
        let coordinator = MerchantOperationsCoordinator(reader: reader, destination: .template(71))
        await coordinator.load(); var edited = source; edited.storyTimeline.update(1, text: "New")
        coordinator.edit(.template(edited)); coordinator.prepare(); let review = try XCTUnwrap(coordinator.confirmation)
        reader.switchAccount(); await coordinator.confirm(review); XCTAssertEqual(reader.saveCount, 0)
    }
}

private final class TimelineTransport: HTTPTransport {
    var replies: [String] = [], requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); guard !replies.isEmpty else { throw APIError.malformedResponse }
        return (Data(replies.removeFirst().utf8), 200)
    }
}
@MainActor private final class TimelineJournal: OperationPendingJournal {
    var record: OperationPendingRecord?
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { record }
    func write(_ record: OperationPendingRecord) throws { self.record = record }
    func clear(_ record: OperationPendingRecord) throws { self.record = nil }
}
@MainActor final class MerchantTemplateStoryTimelineServiceTests: XCTestCase {
    private func exerciseSave(clear: Bool) async throws {
        let access = #"{"code":200,"data":{"active":true,"merchant":{"id":31},"roleCode":"MERCHANT_OWNER","permissions":["merchant:project:manage"]}}"#
        let initial = #"{"code":200,"data":{"id":71,"title":"Timeline","validationMethod":2,"storyText":"Original story"}}"#
        let canonicalJSON = clear ? "" : #"[{"text":"Server story","tag":"Evening","imgs":["/canonical.jpg"]}]"#
        let canonicalText = clear ? "" : "Server summary"
        let returned: [String: Any] = ["code": 200, "data": ["id": 71, "title": "Timeline", "validationMethod": 2, "storyText": canonicalText, "storyJson": canonicalJSON]]
        let transport = TimelineTransport()
        transport.replies = [access, initial, access, initial, access, initial, #"{"code":200,"data":71}"#, access,
                             String(decoding: try JSONSerialization.data(withJSONObject: returned), as: UTF8.self)]
        let api = try APIConfiguration(baseURL: URL(string: "https://example.test/prod-api")!)
        let session = try MerchantOperationsSession(accountID: 7, epoch: 1, token: "synthetic-token", storageNamespace: "timeline-test")
        let approval = try OperationEndpointApproval(baseURL: api.baseURL, namespace: session.storageNamespace, accountID: session.accountID, paths: ["api/merchant/city-node/template/submit"])
        let journal = TimelineJournal()
        let reader = MerchantOperationsSessionReader(service: MerchantOperationsService(configuration: api, transport: transport), currentSession: { session }, approval: approval, journal: journal)
        let coordinator = MerchantOperationsCoordinator(reader: reader, destination: .template(71))
        await coordinator.load(); var edited = timelineTemplate()
        if clear { edited.storyTimeline.setEnabled(false) } else { edited.storyTimeline.update(1, text: "Proposed story", tag: "Morning") }
        coordinator.edit(.template(edited)); coordinator.prepare(); let review = try XCTUnwrap(coordinator.confirmation)
        await coordinator.confirm(review)
        let saves = transport.requests.filter { $0.url?.path.hasSuffix("/template/submit") == true }
        XCTAssertEqual(saves.count, 1)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(saves.first?.httpBody)) as? [String: Any])
        XCTAssertEqual(body["storyText"] as? String, edited.storyTimeline.fields["storyText"])
        XCTAssertEqual(body["storyJson"] as? String, edited.storyTimeline.fields["storyJson"])
        guard case .template(let source) = coordinator.draft else { return XCTFail() }
        XCTAssertEqual(source.storyTimeline.fields["storyJson"], canonicalJSON)
        XCTAssertEqual(source.storyTimeline.fields["storyText"], canonicalText); XCTAssertFalse(source.storyTimeline.isEdited)
        XCTAssertEqual(transport.requests.last?.url?.path, "/prod-api/api/template/myinfo")
        XCTAssertNil(journal.record); XCTAssertFalse(coordinator.isDirty)
        let count = transport.requests.count; await coordinator.confirm(review); XCTAssertEqual(transport.requests.count, count)
    }
    func testApprovedFakeTransportSendsTwoFieldsAndCanonicalReadbackWins() async throws { try await exerciseSave(clear: false) }
    func testApprovedClearSendsTwoEmptyStringsAndReadsBackEmptyTimeline() async throws { try await exerciseSave(clear: true) }
    func testWithoutApprovalNothingIsSent() async throws {
        let transport = TimelineTransport()
        let api = try APIConfiguration(baseURL: URL(string: "https://example.test/prod-api")!)
        let session = try MerchantOperationsSession(accountID: 7, epoch: 1, token: "synthetic-token", storageNamespace: "timeline-denied")
        let reader = MerchantOperationsSessionReader(service: MerchantOperationsService(configuration: api, transport: transport), currentSession: { session })
        XCTAssertFalse(reader.canSave)
        do { _ = try await reader.saveTemplateReviewed(timelineTemplate(), baseline: timelineTemplate()); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantOperationsFailure, .liveWritesDisabled) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
}
