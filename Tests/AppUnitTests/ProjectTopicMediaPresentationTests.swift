import XCTest
import UIKit
@testable import Questify

#if DEBUG
/// Native decoding/cropping plus synthetic HTTP. No live service/account is used.
@MainActor final class ProjectTopicMediaPresentationTests: XCTestCase {
    @MainActor private final class Owner {
        var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "topic-media-host")
        var approval: ProjectTopicImageUploadApproval?
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var failed = false
        var beforeReply: (() -> Void)?
        var reference = "https://media.example/topic.jpg?token=e%CC%81"
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); beforeReply?()
            if failed { throw URLError(.timedOut) }
            return (try JSONEncoder().encode(["code": ProjectEditJSON.number(200), "url": .string(reference)]), 200)
        }
    }
    @MainActor private final class Picker: ProjectTopicMediaPicking {
        let image: RetainedSelectedImage
        var held = false
        var waiting: [CheckedContinuation<RetainedSelectedImage?, Error>] = []
        init(_ image: RetainedSelectedImage) { self.image = image }
        func select() async throws -> RetainedSelectedImage? {
            if held { return try await withCheckedThrowingContinuation { waiting.append($0) } }
            return image
        }
        func cancel() {} // Deliberately uncooperative to prove late callback fencing.
        func finishFirst() { waiting.removeFirst().resume(returning: image) }
    }
    private struct Context {
        let owner: Owner, wire: Wire, picker: Picker, storage: ProjectEditMemoryStorage
        let editor: ProjectEditModel, controller: ProjectTopicMediaPresentation
    }
    private func context() async throws -> Context {
        let owner = Owner(), wire = Wire(), storage = ProjectEditMemoryStorage(), session = try XCTUnwrap(owner.session)
        let api = try APIConfiguration(baseURL: URL(string: "https://api.example")!)
        let policy = try ProjectTopicMediaPolicy(id: UUID(), revision: 1, maximumItems: 1, maximumTotalBytes: 1_000_000, mixing: .singleKind,
            kinds: [.init(kind: .image, mimeTypes: ["image/jpeg"], maximumBytes: 1_000_000, maximumWidth: 4096,
                          maximumHeight: 4096, maximumPixels: 16_777_216, maximumDurationMilliseconds: nil)])
        owner.approval = try .init(baseURL: api.baseURL, namespace: session.storageNamespace, accountID: 7,
                                  fields: [.cover, .gallery], approvedOrigins: ["https://media.example"], policy: policy, nativePicker: true)
        let source = ProjectTopicImageUploadClient(configuration: api, approval: owner.approval, transport: wire,
            credentials: { owner.session.flatMap { try? .init(session: $0, token: "synthetic-topic-token") } }, currentApproval: { owner.approval })
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: 128, height: 96), format: format).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 128, height: 96))
        }
        let picker = try Picker(RetainedImageSanitizer.sanitize(XCTUnwrap(rendered.jpegData(compressionQuality: 0.9))))
        let coordinator = ProjectEditCoordinator(initial: .init(draft: ProjectEditSyntheticFixtures.draft()), service: ProjectEditSyntheticService(),
            store: .init(storage: storage), topicImageSource: source, currentSession: { owner.session })
        let editor = ProjectEditModel(coordinator: coordinator); await editor.load(); editor.saveLocal()
        return .init(owner: owner, wire: wire, picker: picker, storage: storage, editor: editor, controller: .init(editor: editor, picker: picker))
    }
    private func open(_ c: Context, _ field: ProjectTopicImageField = .cover) throws -> ProjectTopicMediaPresentation.Opening {
        c.controller.open(field); return try XCTUnwrap(c.controller.opening)
    }
    private func selected(_ c: Context, _ original: ProjectTopicMediaPresentation.Opening) async throws {
        c.controller.choose(original)
        for _ in 0..<100 where c.controller.crop == nil { await Task.yield() }
        let crop = try XCTUnwrap(c.controller.crop), rect = try ProjectTopicImageCropRect(image: crop.image, field: original.field)
        c.controller.confirmCrop(crop, rect: rect, original: original)
        XCTAssertEqual(c.controller.state, .preview); XCTAssertNotNil(c.controller.thumbnail)
        XCTAssertTrue(c.wire.requests.isEmpty)
    }
    private func uploaded(_ c: Context, _ original: ProjectTopicMediaPresentation.Opening) async throws {
        try await selected(c, original); c.controller.upload(original)
        for _ in 0..<100 where c.controller.state == .uploading { await Task.yield() }
        XCTAssertEqual(c.controller.state, .uploaded)
    }
    func testCoverOnlyAppliesExactReturnedURLAfterExplicitConfirmation() async throws {
        let c = try await context(), original = try open(c), before = c.editor.draft.imgUrl
        try await uploaded(c, original); XCTAssertEqual(c.editor.draft.imgUrl, before)
        c.controller.apply(original); XCTAssertNil(c.controller.opening)
        XCTAssertEqual(Array(c.editor.draft.imgUrl.utf8), Array(c.wire.reference.utf8)); XCTAssertEqual(c.wire.requests.count, 1)
        c.controller.apply(original); XCTAssertEqual(c.wire.requests.count, 1)
        let stored = ProjectEditLocalStore(storage: c.storage).load(session: original.context.session, identity: original.context.identity,
                                                                   baseline: try XCTUnwrap(c.editor.coordinator.snapshot).draft)
        guard case .ready(let record) = stored else { return XCTFail() }
        XCTAssertEqual(record.draft.imgUrl, c.wire.reference)
    }
    func testGalleryPreservesExistingSemicolonBytesAndCapsNine() async throws {
        let c = try await context(); c.editor.draft.imgArr = "https://media.example/a.jpg;https://media.example/b.jpg"
        let before = c.editor.draft.imgArr, original = try open(c, .gallery)
        try await uploaded(c, original); c.controller.apply(original)
        XCTAssertEqual(c.editor.draft.imgArr, before + "," + c.wire.reference)
        c.editor.draft.imgArr = Array(repeating: "https://media.example/a.jpg", count: 9).joined(separator: ",")
        XCTAssertFalse(c.controller.canOpen(.gallery)); XCTAssertTrue(c.controller.canOpen(.cover))
    }
    func testSameByteDraftReplacementAndAccountChangeRejectOldApply() async throws {
        let c = try await context(), original = try open(c)
        try await uploaded(c, original); let before = c.editor.draft
        c.editor.draft = before
        XCTAssertFalse(c.controller.isCurrent(original)); c.controller.apply(original)
        XCTAssertEqual(c.editor.draft, before)
        c.owner.session = try .init(accountID: 8, epoch: 2, storageNamespace: original.context.session.storageNamespace)
        c.controller.apply(original); XCTAssertEqual(c.editor.draft, before); c.controller.synchronize()
        XCTAssertNil(c.controller.opening); XCTAssertNil(c.controller.thumbnail)
    }
    func testLocalSaveRetryNeverRepeatsUpload() async throws {
        let c = try await context(), original = try open(c), before = c.editor.draft
        try await uploaded(c, original); c.storage.failWrites = true; c.controller.apply(original)
        XCTAssertEqual(c.controller.state, .localSaveFailed); XCTAssertEqual(c.editor.draft, before)
        c.storage.failWrites = false; c.controller.apply(original)
        XCTAssertEqual(c.editor.draft.imgUrl, c.wire.reference); XCTAssertEqual(c.wire.requests.count, 1)
    }
    func testUnknownHasNoAutomaticOrRepeatedUploadAndNoApply() async throws {
        let c = try await context(), original = try open(c), before = c.editor.draft
        try await selected(c, original); c.wire.failed = true; c.controller.upload(original)
        for _ in 0..<100 where c.controller.state == .uploading { await Task.yield() }
        XCTAssertEqual(c.controller.state, .unknown)
        c.controller.upload(original); c.controller.apply(original); c.controller.choose(original)
        XCTAssertEqual(c.wire.requests.count, 1); XCTAssertEqual(c.editor.draft, before)
    }
    func testCloseQueuedUploadAndOldDismissCannotMutateReplacement() async throws {
        let c = try await context(), old = try open(c), binding = c.controller.binding(old)
        try await selected(c, old); c.controller.upload(old); c.controller.close(old)
        let current = try open(c, .gallery); binding.wrappedValue = nil; c.controller.close(old); c.controller.apply(old)
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(c.controller.opening?.id, current.id); XCTAssertTrue(c.wire.requests.isEmpty)
    }
    func testCancelledPickerLateCompletionCannotReplaceNewCrop() async throws {
        let c = try await context(), original = try open(c); c.picker.held = true
        c.controller.choose(original)
        for _ in 0..<100 where c.picker.waiting.isEmpty { await Task.yield() }
        XCTAssertEqual(c.picker.waiting.count, 1); c.controller.cancelSelection(original); c.controller.choose(original)
        for _ in 0..<100 where c.picker.waiting.count < 2 { await Task.yield() }
        XCTAssertEqual(c.picker.waiting.count, 2); c.picker.finishFirst()
        for _ in 0..<30 { await Task.yield() }
        XCTAssertNil(c.controller.crop); XCTAssertEqual(c.controller.state, .picking)
        c.picker.finishFirst()
        for _ in 0..<100 where c.controller.crop == nil { await Task.yield() }
        XCTAssertNotNil(c.controller.crop); XCTAssertTrue(c.wire.requests.isEmpty)
    }
    func testSourceRevocationAndFieldModeWithdrawalExpireSelection() async throws {
        let c = try await context(), original = try open(c); try await selected(c, original)
        c.owner.approval = nil; c.controller.upload(original); c.controller.synchronize()
        XCTAssertNil(c.controller.opening); XCTAssertTrue(c.wire.requests.isEmpty)
        c.editor.draft.preserved["publishMode"] = .string("simple")
        XCTAssertNil(c.editor.topicMediaContext); XCTAssertFalse(c.controller.canOpen(.cover))
    }
    func testNativeInspectionEvidenceAndCropRatiosAreActualPixels() async throws {
        let c = try await context()
        for field in [ProjectTopicImageField.cover, .gallery] {
            let original = try open(c, field); try await selected(c, original)
            let facts = try XCTUnwrap(c.controller.preview?.items.first)
            XCTAssertEqual(facts.kind, .image); XCTAssertEqual(facts.mimeType, "image/jpeg")
            XCTAssertEqual(facts.width * UInt64(field.heightUnits), facts.height * UInt64(field.widthUnits))
            XCTAssertEqual(facts.contentSHA256.count, 64); XCTAssertGreaterThan(facts.byteCount, 0)
            c.controller.cancelSelection(original); XCTAssertNil(c.controller.preview); c.controller.close(original)
        }
    }
    func testGalleryAggregateLengthFailureNeverTruncatesOrSaves() async throws {
        let c = try await context(); c.editor.draft.imgArr = "https://media.example/" + String(repeating: "a", count: 1950)
        let before = c.editor.draft, original = try open(c, .gallery)
        try await uploaded(c, original); c.controller.apply(original)
        XCTAssertEqual(c.controller.state, .localSaveFailed); XCTAssertEqual(c.editor.draft, before)
        XCTAssertEqual(c.wire.requests.count, 1)
    }
    func testNewEditorVisitAndLateUploadCannotChangeOriginalDraft() async throws {
        let c = try await context(), original = try open(c), before = c.editor.draft
        try await selected(c, original)
        c.wire.beforeReply = { c.editor.coordinator.beginEditorVisit(UUID()) }
        c.controller.upload(original)
        for _ in 0..<100 where c.wire.requests.isEmpty { await Task.yield() }
        c.controller.apply(original); c.controller.synchronize()
        XCTAssertEqual(c.editor.draft, before); XCTAssertNil(c.controller.receipt); XCTAssertNil(c.controller.opening)
    }
    func testObservedApprovalWithdrawalCannotReviveSameGrantPreview() async throws {
        let c = try await context(), original = try open(c), approval = c.owner.approval
        try await selected(c, original); c.owner.approval = nil
        XCTAssertFalse(c.controller.isCurrent(original))
        c.owner.approval = approval
        XCTAssertFalse(c.controller.isCurrent(original)); c.controller.upload(original)
        XCTAssertTrue(c.wire.requests.isEmpty); c.controller.synchronize(); XCTAssertNil(c.controller.opening)
    }
    func testExactTopicRouteRejectsStoryBoundaryAndBusinessType() async throws {
        let c = try await context(), original = try open(c); try await uploaded(c, original)
        let api = try XCTUnwrap(URL(string: "https://api.example")), request = try XCTUnwrap(c.wire.requests.first)
        XCTAssertEqual(ProjectTopicImageCompositionRoute.field(request, baseURL: api), .cover)
        XCTAssertFalse(ProjectStoryImageCompositionRoute.accepts(request, baseURL: api))
        var tampered = request
        tampered.httpBody = Data(String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self).replacingOccurrences(of: "image_3_4", with: "image_free").utf8)
        XCTAssertNil(ProjectTopicImageCompositionRoute.field(tampered, baseURL: api))
        tampered = request; tampered.url = URL(string: "https://api.example/api/common/uploadOSS?topicId=1")
        XCTAssertNil(ProjectTopicImageCompositionRoute.field(tampered, baseURL: api))
    }
}
#endif
