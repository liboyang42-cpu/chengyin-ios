import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SwiftUI
import UIKit
@testable import Questify

@MainActor private final class CoverJournal: OperationPendingJournal {
    var records: [String: OperationPendingRecord] = [:]
    var fails = false
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? {
        if fails { throw APIError.malformedResponse }; return records[ownerKey + targetKey]
    }
    func write(_ record: OperationPendingRecord) throws {
        if fails { throw APIError.malformedResponse }
        let key = record.ownerKey + record.targetKey
        guard records[key] == nil || records[key]?.operationID == record.operationID else { throw APIError.invalidRequest }
        records[key] = record
    }
    func clear(_ record: OperationPendingRecord) throws {
        guard !fails, records[record.ownerKey + record.targetKey] == record else { throw APIError.invalidRequest }
        records[record.ownerKey + record.targetKey] = nil
    }
}
@MainActor private final class CoverWire: HTTPTransport {
    var requests: [URLRequest] = []
    var bytes = Data(#"{"code":200,"url":"https://images.example.test/activity.jpg?version=original"}"#.utf8)
    var status = 200
    var fail = false
    var held = false
    var continuation: CheckedContinuation<(Data, Int), Error>?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if held { return try await withCheckedThrowingContinuation { continuation = $0 } }
        if fail { throw URLError(.networkConnectionLost) }; return (bytes, status)
    }
}
@MainActor private final class CoverHarness {
    let configuration = try! APIConfiguration(baseURL: URL(string: "https://cover.example.test")!)
    let session = PublishingSession(namespace: "cover-synthetic", accountID: 7, epoch: UUID(), role: "club", region: .china)
    var credential: PublishingCredentials?
    var grant: ActivityCoverApproval?
    let wire = CoverWire(), journal = CoverJournal()
    lazy var service = makeService()
    init(approved: Bool = true) throws {
        credential = try .init(session: session, token: "synthetic-cover-token")
        if approved { grant = try .init(endpoint: .init(baseURL: configuration.baseURL, namespace: session.namespace, accountID: session.accountID, paths: [ActivityCoverService.path]), revision: UUID(), approvedOrigins: ["https://images.example.test"], nativePicker: true) }
    }
    func makeService() -> ActivityCoverService {
        ActivityCoverService(configuration: configuration, transport: wire, approval: grant, currentApproval: { [weak self] in self?.grant }, credentials: { [weak self] in self?.credential }, journal: journal)
    }
    func image(width: Int = 160, height: Int = 90) throws -> RetainedSelectedImage { try .init(jpeg: Data([255,216,255,224,7,255,217]), width: width, height: height) }
    func review(target: ActivityCoverTarget = .existing(41)) throws -> ActivityCoverReview { try service.prepare(image(), target: target, session: session) }
}

@MainActor private final class CoverPage {
    let harness: CoverHarness
    let owner: ActivityCoverAuthoringOwner
    var draft = ActivityPublishDraft()
    var identity = UUID()
    var account: PublishingSession?
    var allowed = true
    var applied = 0
    init(approved: Bool = true, picker: (any OwnedTopicCoverSelecting)? = nil) throws {
        owner = ActivityCoverAuthoringOwner(picker: picker)
        harness = try CoverHarness(approved: approved); account = harness.session
        draft.name = "Original draft e\u{301}"; draft.description = "Keep all content"; draft.coverURL = "https://images.example.test/original.jpg"
        owner.bind(read: { [weak self] in
            guard let self else { return nil }
            return .init(session: self.account, target: .newDraft(self.identity), draft: ProjectEditPendingMaterials.exactData(self.draft), reference: self.draft.coverURL, editable: self.allowed)
        }, apply: { [weak self] value in
            guard let self, self.allowed else { return false }; self.draft.coverURL = value; self.applied += 1; return true
        }, service: { [weak self] in self?.harness.service })
        owner.appear(active: true)
    }
    func open() { owner.openAction()() }
    func stage() throws { owner.stageForReview(try harness.image()) }
    func uploaded() async throws -> ActivityCoverReceipt {
        open(); try stage(); let review = try XCTUnwrap(owner.review); owner.uploadAction(review)()
        while owner.busy { await Task.yield() }; return try XCTUnwrap(owner.receipt)
    }
}
@MainActor final class ActivityCoverAuthoringOwnerTests: XCTestCase {
    func testNewActivityChooseReviewUploadUseChangesOnlyCoverAfterExplicitUse() async throws {
        let page = try CoverPage(), original = page.draft
        let receipt = try await page.uploaded(); XCTAssertEqual(page.draft, original); XCTAssertEqual(page.applied, 0)
        let action = page.owner.applyAction(receipt); action(); action()
        var expected = original; expected.coverURL = receipt.reference
        XCTAssertEqual(page.draft, expected); XCTAssertEqual(page.applied, 1); XCTAssertFalse(page.owner.isOpen)
    }
    func testCancellationBeforeUploadKeepsOriginalDraftAndNoRequest() throws {
        let page = try CoverPage(), original = page.draft; page.open(); try page.stage(); page.owner.close()
        XCTAssertEqual(page.draft, original); XCTAssertTrue(page.harness.wire.requests.isEmpty); XCTAssertFalse(page.owner.isOpen)
    }
    func testCancelKnownUploadedImageKeepsOriginalDraftAndAllowsNewExplicitRound() async throws {
        let page = try CoverPage(), original = page.draft; _ = try await page.uploaded(); page.owner.close()
        XCTAssertEqual(page.draft, original); XCTAssertFalse(page.owner.isOpen)
        page.open(); XCTAssertEqual(page.owner.status, "ready"); XCTAssertTrue(page.owner.canChoose)
    }
    func testDefiniteUploadFailureRetainsReviewImageForExplicitRetryOnly() async throws {
        let page = try CoverPage(); page.open(); try page.stage(); let old = try XCTUnwrap(page.owner.review)
        page.harness.wire.bytes = Data(#"{"code":422}"#.utf8); page.owner.uploadAction(old)()
        while page.owner.busy { await Task.yield() }
        XCTAssertEqual(page.owner.status, "rejected"); XCTAssertNotEqual(page.owner.review?.id, old.id)
        XCTAssertEqual(page.owner.review?.image, old.image); XCTAssertEqual(page.harness.wire.requests.count, 1)
        page.owner.uploadAction(old)(); XCTAssertEqual(page.harness.wire.requests.count, 1)
    }
    func testUnknownUploadCannotReopenRetryAndNeverChangesDraft() async throws {
        let page = try CoverPage(), original = page.draft; page.open(); try page.stage()
        let review = try XCTUnwrap(page.owner.review); page.harness.wire.fail = true; page.owner.uploadAction(review)()
        while page.owner.busy { await Task.yield() }
        XCTAssertEqual(page.owner.status, "unknown"); XCTAssertNil(page.owner.review); XCTAssertFalse(page.owner.canChoose)
        page.owner.close(); page.open(); XCTAssertEqual(page.owner.status, "unknown")
        XCTAssertEqual(page.draft, original); XCTAssertEqual(page.harness.wire.requests.count, 1)
    }
    func testCurrentDraftChangeRejectsOldUploadedApplyAndPreservesNewInput() async throws {
        let page = try CoverPage(); let receipt = try await page.uploaded(), apply = page.owner.applyAction(receipt)
        page.draft.name = "New draft input"; apply()
        XCTAssertEqual(page.draft.name, "New draft input"); XCTAssertTrue(page.draft.coverURL.hasSuffix("original.jpg")); XCTAssertEqual(page.applied, 0)
    }
    func testAccountChangeRejectsOldUploadAndClearCallbacks() throws {
        let page = try CoverPage(); let clear = page.owner.clearAction(); page.open(); try page.stage()
        let upload = page.owner.uploadAction(try XCTUnwrap(page.owner.review))
        page.account = nil; page.harness.credential = nil; upload(); clear()
        XCTAssertTrue(page.harness.wire.requests.isEmpty); XCTAssertEqual(page.applied, 0)
    }
    func testTrueDepartureAndHiddenForegroundCannotUseOldOpenOrApply() async throws {
        let page = try CoverPage(); let opening = page.owner.openAction(); let receipt = try await page.uploaded()
        let apply = page.owner.applyAction(receipt); page.owner.disappear(); page.owner.setActive(true); apply(); opening()
        XCTAssertEqual(page.applied, 0); XCTAssertFalse(page.owner.isOpen); XCTAssertFalse(page.owner.canOpen)
    }
    func testVisibleBackgroundRetiresOldReviewWithoutSending() throws {
        let page = try CoverPage(); page.open(); try page.stage(); let action = page.owner.uploadAction(try XCTUnwrap(page.owner.review))
        page.owner.setActive(false); page.owner.setActive(true); action()
        XCTAssertTrue(page.harness.wire.requests.isEmpty); XCTAssertFalse(page.owner.isOpen)
    }
    func testOldOpenAndRemoveCannotCrossNewDraftIncarnation() throws {
        let page = try CoverPage(), clear = page.owner.clearAction(), open = page.owner.openAction()
        page.identity = UUID(); clear(); open()
        XCTAssertEqual(page.applied, 0); XCTAssertFalse(page.owner.isOpen)
    }
    func testRemoveOnlyLocalCoverAndNoWriteOrSaveIsTriggered() throws {
        let page = try CoverPage(), original = page.draft; page.owner.clearAction()()
        var expected = original; expected.coverURL = ""
        XCTAssertEqual(page.draft, expected); XCTAssertEqual(page.applied, 1); XCTAssertTrue(page.harness.wire.requests.isEmpty)
    }
    func testPreviewIsExplicitAndDisappearsWhenSourceReferenceChanges() throws {
        let page = try CoverPage(); XCTAssertNil(page.owner.visiblePreviewReference)
        page.owner.previewAction()(); XCTAssertEqual(page.owner.visiblePreviewReference, page.draft.coverURL)
        page.draft.coverURL = "https://images.example.test/replacement.jpg"; XCTAssertNil(page.owner.visiblePreviewReference)
    }
    func testReadOnlyAndUnknownActivityCannotOpenOrClear() throws {
        let page = try CoverPage(); page.allowed = false; page.owner.openAction()(); page.owner.clearAction()()
        XCTAssertFalse(page.owner.isOpen); XCTAssertEqual(page.applied, 0)
    }
    func testDefaultApprovalOffPreservesLocalRemoveButDisablesPickerAndUpload() throws {
        let page = try CoverPage(approved: false); page.open()
        XCTAssertEqual(page.owner.status, "unavailable"); XCTAssertFalse(page.owner.canChoose)
        try page.stage(); XCTAssertNil(page.owner.review); XCTAssertTrue(page.harness.wire.requests.isEmpty)
    }
    func testSanitizedNativeCropUsesExistingExactSixteenByNineRenderer() throws {
        let size = CGSize(width: 160, height: 120), format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in UIColor.blue.setFill(); context.fill(CGRect(origin: .zero, size: size)) }
        let bytes = try XCTUnwrap(image.jpegData(compressionQuality: 0.9)), source = try RetainedImageSanitizer.sanitize(bytes)
        let rect = try MerchantImageCropRect(sourceWidth: source.width, sourceHeight: source.height, aspect: .gallery)
        let output = try MerchantImageCropRenderer.render(source, rect: rect)
        XCTAssertEqual(output.width * 9, output.height * 16); XCTAssertNotNil(UIImage(data: output.jpeg))
    }
    func testKnownReceiptDiscardNeverClearsUnknownDifferentAttempt() async throws {
        let page = try CoverPage(); let receipt = try await page.uploaded()
        let old = try XCTUnwrap(page.harness.journal.records.values.first)
        page.harness.journal.records[old.ownerKey + old.targetKey] = .init(operationID: UUID(), ownerKey: old.ownerKey, targetKey: old.targetKey)
        page.owner.close(); XCTAssertTrue(page.owner.isOpen); XCTAssertEqual(page.owner.status, "unknown")
        XCTAssertFalse(page.harness.service.discard(receipt, current: { true }))
    }
    func testExistingEditorAtomicCoverPairPreservesAllOtherFieldsAndUnknownJSON() async throws {
        @MainActor final class Store: ProjectEditDataStorage {
            var values: [String: Data] = [:]
            func read(_ key: String) throws -> Data? { values[key] }
            func write(_ data: Data, key: String) throws { values[key] = data }
            func remove(_ key: String) throws { values[key] = nil }
        }
        let h = try CoverHarness(), store = Store()
        h.wire.bytes = Data(#"{"code":200,"data":{"id":41,"memberId":7,"timeLocationLocked":true,"name":"Original","imgUrl":"old-cover","imgArr":"old-array","future":{"value":"Keep"}}}"#.utf8)
        let grants = try ActivityEditingGrants(read: .init(baseURL: h.configuration.baseURL, namespace: h.session.namespace, accountID: 7, paths: [ActivityEditingService.readPath]))
        let service = ActivityEditingService(configuration: h.configuration, transport: h.wire, grants: grants,
            drafts: ActivityEditingDraftStore(storage: store, journal: h.journal), credentials: { h.credential })
        let editor = ActivityEditingController(activityID: 41, session: h.session, service: service)
        editor.appear(active: true); await editor.load(); let original = try XCTUnwrap(editor.draft)
        XCTAssertTrue(editor.applyCover("https://images.example.test/new.jpg", expected: original))
        let changed = try XCTUnwrap(editor.draft)
        XCTAssertEqual(changed.text(.imgUrl), "https://images.example.test/new.jpg"); XCTAssertEqual(changed.text(.imgArr), changed.text(.imgUrl))
        XCTAssertEqual(changed.source, original.source)
        for field in ActivityEditingField.allCases where field != .imgUrl && field != .imgArr { XCTAssertEqual(changed.text(field), original.text(field)) }
        XCTAssertFalse(editor.applyCover("old callback", expected: original)); XCTAssertEqual(h.wire.requests.count, 1); XCTAssertTrue(store.values.isEmpty)
    }
}

@MainActor private final class CoverHeldPicker: OwnedTopicCoverSelecting {
    var pending: CheckedContinuation<RetainedSelectedImage?, Error>?
    var cancelled = 0
    func select() async throws -> RetainedSelectedImage? { try await withCheckedThrowingContinuation { pending = $0 } }
    func cancel() { cancelled += 1 }
}
extension ActivityCoverAuthoringOwnerTests {
    func testNativePickerCoveragePreservesOriginalOwnerUntilReturningToCrop() async throws {
        let picker = CoverHeldPicker(), page = try CoverPage(picker: picker)
        page.open(); page.owner.chooseAction()()
        while picker.pending == nil { await Task.yield() }
        page.owner.parentDisappeared(departing: false, covered: true)
        XCTAssertTrue(page.owner.current)
        picker.pending?.resume(returning: try page.harness.image()); picker.pending = nil
        while page.owner.selecting { await Task.yield() }
        XCTAssertNotNil(page.owner.crop); page.owner.parentAppeared(); XCTAssertTrue(page.owner.current)
    }
    func testActualDepartureDuringNativePickerRejectsLateSelectionWithoutNewOwnerMutation() async throws {
        let picker = CoverHeldPicker(), page = try CoverPage(picker: picker)
        page.open(); page.owner.chooseAction()()
        while picker.pending == nil { await Task.yield() }
        let pending = try XCTUnwrap(picker.pending); picker.pending = nil
        page.owner.parentDisappeared(departing: true, covered: true)
        page.identity = UUID(); page.owner.appear(active: true); page.open()
        pending.resume(returning: try page.harness.image()); await Task.yield()
        XCTAssertNil(page.owner.crop); XCTAssertNil(page.owner.review); XCTAssertEqual(picker.cancelled, 1)
        XCTAssertEqual(page.applied, 0)
    }
    func testQueuedOldCloseAndChooseCannotAffectFreshRound() throws {
        let page = try CoverPage(); page.open()
        let close = page.owner.closeAction(), choose = page.owner.chooseAction()
        page.owner.close(); page.open(); close(); choose()
        XCTAssertTrue(page.owner.isOpen); XCTAssertFalse(page.owner.selecting)
    }
}


extension ActivityCoverAuthoringOwnerTests {
    func testAccountHandlerWhileHiddenCannotOpenOrClearEvenAfterForeground() throws {
        let page = try CoverPage(), original = page.draft
        let oldOpen = page.owner.openAction(), oldClear = page.owner.clearAction()
        page.owner.disappear()
        page.account = PublishingSession(namespace: "cover-synthetic", accountID: 8, epoch: UUID(), role: "club", region: .china)
        // Invoke the exact handler mounted by ActivityPublishingView.onChange(account).
        page.owner.accountChanged(); page.owner.setActive(true)
        oldOpen(); oldClear(); page.owner.openAction()(); page.owner.clearAction()()
        XCTAssertFalse(page.owner.canOpen); XCTAssertFalse(page.owner.isOpen)
        XCTAssertEqual(page.draft, original); XCTAssertEqual(page.applied, 0)
        XCTAssertTrue(page.harness.wire.requests.isEmpty)
    }
    func testHiddenAccountHandlerRequiresRealReturnBeforeNewExplicitLocalAction() throws {
        let page = try CoverPage(), oldOpen = page.owner.openAction(), oldClear = page.owner.clearAction()
        page.owner.disappear(); page.account = nil; page.owner.accountChanged(); page.owner.setActive(true)
        XCTAssertFalse(page.owner.canOpen)
        page.owner.appear(active: true)
        XCTAssertTrue(page.owner.canOpen)
        oldOpen(); oldClear(); XCTAssertFalse(page.owner.isOpen); XCTAssertEqual(page.applied, 0)
        page.owner.clearAction()(); XCTAssertEqual(page.applied, 1); XCTAssertEqual(page.draft.coverURL, "")
        XCTAssertTrue(page.harness.wire.requests.isEmpty)
    }
    func testVisibleAccountHandlerRetiresOldRoundWithoutDisablingCurrentLocalEditing() throws {
        let page = try CoverPage(); let oldClear = page.owner.clearAction(); page.open(); try page.stage()
        let oldUpload = page.owner.uploadAction(try XCTUnwrap(page.owner.review))
        page.account = nil; page.owner.accountChanged()
        XCTAssertNil(page.owner.review); XCTAssertFalse(page.owner.isOpen); XCTAssertTrue(page.owner.canOpen)
        oldClear(); oldUpload(); XCTAssertEqual(page.applied, 0); XCTAssertTrue(page.harness.wire.requests.isEmpty)
        page.owner.clearAction()(); XCTAssertEqual(page.applied, 1)
        page.owner.openAction()(); XCTAssertTrue(page.owner.isOpen); XCTAssertFalse(page.owner.canChoose)
    }
}


extension ActivityCoverAuthoringOwnerTests {
    func testRemotePreviewRejectsUnapprovedOriginAndDefaultNilService() throws {
        let page = try CoverPage(); page.draft.coverURL = "https://unapproved.example.test/image.jpg"
        page.owner.previewAction()(); XCTAssertNil(page.owner.visiblePreviewReference)
        let disabled = try CoverPage(approved: false); disabled.owner.previewAction()()
        XCTAssertNil(disabled.owner.visiblePreviewReference)
        XCTAssertTrue(page.harness.wire.requests.isEmpty); XCTAssertTrue(disabled.harness.wire.requests.isEmpty)
    }
    func testApprovedPreviewIsRemovedOnLiveApprovalRevocationAndAccountChange() throws {
        let page = try CoverPage(); page.owner.previewAction()()
        XCTAssertEqual(page.owner.visiblePreviewReference, page.draft.coverURL)
        page.harness.grant = nil; XCTAssertNil(page.owner.visiblePreviewReference)
        let other = try CoverPage(); other.owner.previewAction()(); other.account = nil
        XCTAssertNil(other.owner.visiblePreviewReference)
        XCTAssertTrue(page.harness.wire.requests.isEmpty); XCTAssertTrue(other.harness.wire.requests.isEmpty)
    }
    func testOldLifetimeDisappearAndDetachCannotRetireReplacementRoot() throws {
        let page = try CoverPage(); var oldDepartures = 0, newDepartures = 0
        let a = ActivityCoverLifetimeController(owner: page.owner, departure: { oldDepartures += 1 })
        a.viewDidAppear(false)
        let b = ActivityCoverLifetimeController(owner: page.owner, departure: { newDepartures += 1 })
        b.viewDidAppear(false); page.open(); try page.stage(); let review = try XCTUnwrap(page.owner.review)
        a.viewWillDisappear(false); a.viewDidDisappear(false); a.detach()
        XCTAssertEqual(oldDepartures, 0); XCTAssertEqual(newDepartures, 0)
        XCTAssertTrue(page.owner.owns(b)); XCTAssertTrue(page.owner.current); XCTAssertEqual(page.owner.review, review)
        b.detach(); XCTAssertEqual(newDepartures, 1); XCTAssertFalse(page.owner.current); XCTAssertNil(page.owner.review)
        b.detach(); XCTAssertEqual(newDepartures, 1)
    }
    func testLateOldLifetimeAppearCannotMakeHiddenReplacementVisible() throws {
        let page = try CoverPage(); var departures = 0
        let a = ActivityCoverLifetimeController(owner: page.owner, departure: {})
        let b = ActivityCoverLifetimeController(owner: page.owner, departure: { departures += 1 })
        b.viewDidAppear(false); b.viewWillDisappear(false); b.viewDidDisappear(false)
        XCTAssertEqual(departures, 1); page.owner.setActive(true)
        a.viewDidAppear(false); a.detach()
        XCTAssertFalse(page.owner.canOpen); XCTAssertTrue(page.owner.owns(b)); XCTAssertEqual(departures, 1)
        b.viewDidAppear(false); XCTAssertTrue(page.owner.canOpen)
    }
}
