import XCTest
import UIKit
import PhotosUI
@testable import Questify

@MainActor final class MerchantGalleryBatchTests: XCTestCase {
    private final class Transport: HTTPTransport {
        var calls = 0
        var unknown = false
        var reject = false
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            calls += 1
            if unknown { return (Data("invalid".utf8), 200) }
            if reject { return (Data(#"{"code":400,"msg":"Rejected"}"#.utf8), 400) }
            return (Data("{\"code\":200,\"url\":\"https://media.example.com/\(calls).jpg\"}".utf8), 200)
        }
    }
    @MainActor private final class Harness {
        let batch = MerchantGalleryBatchModel()
        let transport = Transport()
        var bytes: [String: Data] = [:]
        var failApplied = false
        var failBegin = false
        var fence = UUID()
        var scope: RetainedImageScope
        var draft: MerchantOperationsDraft
        var cached: RetainedImageSelectionContext?
        var acquisitions = 0
        var inAppend = false
        lazy var journal = StoredImageUploadJournal(read: { self.bytes[$0] }, write: { data, key in
            let value = try JSONDecoder().decode(ImageUploadJournalEntry.self, from: data)
            if (self.failApplied && value.phase == .locallyApplied) || (self.failBegin && value.phase == .pending) {
                throw ImageUploadJournalFailure.unavailable
            }
            self.bytes[key] = data
        })
        init(count: Int = 0) throws {
            scope = try .init(accountID: 8, epoch: UUID(), realm: "https://api.example.com/",
                destination: .merchant(merchantRowID: 73, field: .gallery), accessRevision: UUID(), namespace: "fixture")
            var decor = try JSONDecoder().decode(MerchantStoreDecor.self, from: Data("{}".utf8)); decor.gallery = (0..<count).map { "https://media.example.com/existing\($0).jpg" }
            draft = .gallery(decor)
        }
        func context() -> RetainedImageSelectionContext? {
            XCTAssertFalse(inAppend, "Do not reacquire context before applyLocally returns")
            if let cached { return cached }
            acquisitions += 1
            let captured = scope
            let uploader = try! RetainedImageHTTPUploader(configuration: .init(baseURL: URL(string: scope.realm)!), transport: transport,
                enabled: true, approvedOrigins: ["https://media.example.com"], currentScope: { self.scope == captured ? captured : nil }, token: { "fixture-token" })
            let value = RetainedImageSelectionContext(scope: captured, currentScope: { self.scope == captured ? captured : nil },
                picker: .init(present: { _ in XCTFail("No OS picker in synthetic test"); return false }, dismiss: {}),
                uploads: .init(uploader: uploader, journal: journal))
            cached = value; return value
        }
        var binding: MerchantGalleryBatchBinding {
            .init(draft: { self.draft }, accessFence: { self.fence }, context: { self.context() }, append: { image, scope, before, after in
                guard self.draft == before, self.scope == scope,
                      (try? image.applying(to: before, expectedScope: scope)) == after else { return false }
                self.inAppend = true
                defer { self.inAppend = false }
                self.draft = after
                // Match normal owner invalidation occurring synchronously inside consumer.
                self.cached?.uploads.clear(); self.cached = nil
                self.scope = try! .init(accountID: scope.accountID, epoch: scope.epoch, realm: scope.realm,
                    destination: scope.destination, accessRevision: UUID(), namespace: scope.namespace)
                return true
            })
        }
        func start(_ images: [RetainedSelectedImage]) {
            batch.install(images, binding: binding, context: context()!, draft: draft, fence: fence)
        }
        var gallery: [String] { if case .gallery(let value) = draft { return value.gallery }; return [] }
    }
    private func image() throws -> RetainedSelectedImage {
        let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = true
        let value = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 90), format: f).image { c in
            UIColor.red.setFill(); c.fill(CGRect(x: 0, y: 0, width: 160, height: 90))
        }
        return try RetainedImageSanitizer.sanitize(XCTUnwrap(value.jpegData(compressionQuality: 0.9)))
    }
    private func crop(_ h: Harness) throws -> RetainedImageUploadReview {
        let draft = try XCTUnwrap(h.batch.cropDraft)
        h.batch.confirmCrop(id: draft.id, rect: try .init(sourceWidth: draft.source.width, sourceHeight: draft.source.height, aspect: .gallery))
        guard case .reviewing(let review) = h.batch.context?.uploads.state else { throw RetainedImageFailure.invalid }
        return review
    }
    private func upload(_ h: Harness) async throws -> RetainedUploadedImage {
        await h.batch.confirmUpload(try crop(h))
        guard case .uploaded(let image) = h.batch.context?.uploads.state else { throw RetainedImageFailure.invalid }
        return image
    }
    func testSeparateReviewAndStableOrderAcrossFreshScopes() async throws {
        let h = try Harness(); h.start([try image(), try image()])
        let firstScope = try XCTUnwrap(h.batch.context?.scope)
        let review = try crop(h); XCTAssertEqual(h.transport.calls, 0)
        await h.batch.confirmUpload(review)
        guard case .uploaded(let uploaded) = h.batch.context?.uploads.state else { return XCTFail() }
        h.batch.use(uploaded)
        XCTAssertEqual(h.batch.appliedCount, 1); XCTAssertEqual(h.acquisitions, 2)
        XCTAssertNotEqual(h.batch.context?.scope.accessRevision, firstScope.accessRevision)
        XCTAssertEqual(h.batch.remainingCount, 1)
        h.batch.use(try await upload(h))
        XCTAssertEqual(h.gallery, ["https://media.example.com/1.jpg", "https://media.example.com/2.jpg"])
        XCTAssertFalse(h.batch.active); XCTAssertFalse(h.batch.blocked); XCTAssertEqual(h.transport.calls, 2)
    }
    func testNinthImageBoundAndOverselection() async throws {
        let h = try Harness(count: 8); h.start([try image(), try image()])
        XCTAssertFalse(h.batch.active); XCTAssertTrue(h.batch.failed); XCTAssertEqual(h.transport.calls, 0)
        h.start([try image()]); h.batch.use(try await upload(h))
        XCTAssertEqual(h.gallery.count, 9); XCTAssertEqual(h.acquisitions, 1)
        h.start([try image()]); XCTAssertFalse(h.batch.active); XCTAssertEqual(h.transport.calls, 1)
    }
    func testFailedDurableAppliedAfterAppendStopsWithoutReacquisition() async throws {
        let h = try Harness(); h.start([try image(), try image()]); let uploaded = try await upload(h)
        h.failApplied = true; h.batch.use(uploaded)
        XCTAssertEqual(h.gallery.count, 1); XCTAssertTrue(h.batch.blocked)
        XCTAssertEqual(h.batch.remainingCount, 0); XCTAssertEqual(h.acquisitions, 1)
        XCTAssertEqual(h.batch.context?.uploads.state, .unknown); XCTAssertEqual(h.transport.calls, 1)
        h.batch.use(uploaded); XCTAssertEqual(h.gallery.count, 1)
        XCTAssertEqual(h.context()?.uploads.state, .unknown)
    }
    func testUnknownStopsWholeQueueAndSurvivesCancel() async throws {
        let h = try Harness(); h.start([try image(), try image()]); h.transport.unknown = true
        await h.batch.confirmUpload(try crop(h)); XCTAssertTrue(h.batch.blocked)
        XCTAssertEqual(h.batch.remainingCount, 0); XCTAssertNil(h.batch.cropDraft)
        h.batch.cancel(); XCTAssertTrue(h.batch.blocked); XCTAssertEqual(h.batch.context?.uploads.state, .unknown)
        XCTAssertEqual(h.transport.calls, 1)
    }
    func testJournalBeginFailureDoesNotTransmit() async throws {
        let h = try Harness(); h.start([try image(), try image()]); h.failBegin = true
        await h.batch.confirmUpload(try crop(h))
        XCTAssertTrue(h.batch.blocked); XCTAssertEqual(h.transport.calls, 0); XCTAssertTrue(h.batch.pending.isEmpty)
    }
    func testPartialSuccessThenRejectionRequiresExplicitSkip() async throws {
        let h = try Harness(); h.start([try image(), try image(), try image()])
        h.batch.use(try await upload(h)); h.transport.reject = true
        await h.batch.confirmUpload(try crop(h))
        XCTAssertEqual(h.gallery.count, 1); XCTAssertEqual(h.batch.remainingCount, 2)
        XCTAssertEqual(h.transport.calls, 2); h.batch.skip()
        XCTAssertEqual(h.batch.remainingCount, 1); XCTAssertNotNil(h.batch.cropDraft)
        XCTAssertEqual(h.transport.calls, 2); h.batch.cancel(); XCTAssertEqual(h.gallery.count, 1)
    }
    func testSkipCancelStaleCropAndAccessRevocationReleaseBytes() throws {
        let h = try Harness(); h.start([try image(), try image()]); let first = try XCTUnwrap(h.batch.cropDraft)
        h.batch.skip(); let next = try XCTUnwrap(h.batch.cropDraft)
        h.batch.confirmCrop(id: first.id, rect: try .init(sourceWidth: 160, sourceHeight: 90, aspect: .gallery))
        XCTAssertEqual(h.batch.cropDraft?.id, next.id)
        h.fence = UUID(); _ = try? crop(h)
        XCTAssertEqual(h.transport.calls, 0); h.batch.cancel()
        XCTAssertNil(h.batch.cropDraft); XCTAssertTrue(h.batch.pending.isEmpty); XCTAssertFalse(h.batch.active)
    }
    func testChangedDraftCannotUploadOrUse() async throws {
        let h = try Harness(); h.start([try image(), try image()]); let review = try crop(h)
        h.draft = .gallery(try JSONDecoder().decode(MerchantStoreDecor.self, from: Data("{}".utf8))); h.fence = UUID()
        await h.batch.confirmUpload(review); XCTAssertEqual(h.transport.calls, 0)
        h.batch.cancel(); XCTAssertTrue(h.batch.pending.isEmpty)
    }
    func testCancelAcknowledgedNeverDeletesOrRetries() async throws {
        let h = try Harness(); h.start([try image(), try image()]); _ = try await upload(h)
        h.batch.cancel(); XCTAssertTrue(h.batch.blocked); XCTAssertEqual(h.gallery.count, 0)
        XCTAssertTrue(h.batch.pending.isEmpty); XCTAssertEqual(h.transport.calls, 1)
        h.cached = nil; XCTAssertEqual(h.context()?.uploads.state, .unknown)
    }
    func testReplacementPreservesPositionAndRejectsOldCropOrBatch() throws {
        let h = try Harness(); h.start([try image(), try image()])
        let batch = try XCTUnwrap(h.batch.batchID), old = try XCTUnwrap(h.batch.cropDraft)
        let replacement = try image(); h.batch.stageReplacement(replacement, batch: batch)
        XCTAssertEqual(h.batch.cropDraft?.source.id, replacement.id); XCTAssertEqual(h.batch.remainingCount, 2)
        h.batch.confirmCrop(id: old.id, rect: try .init(sourceWidth: 160, sourceHeight: 90, aspect: .gallery))
        XCTAssertEqual(h.batch.cropDraft?.source.id, replacement.id)
        h.batch.cancel(); h.start([try image()]); let next = h.batch.cropDraft?.id
        h.batch.stageReplacement(replacement, batch: batch); XCTAssertEqual(h.batch.cropDraft?.id, next)
        XCTAssertEqual(h.transport.calls, 0)
    }
    func testDisabledReplacementPreservesCurrentAndCancelAllDropsIt() async throws {
        let h = try Harness(); h.start([try image(), try image()]); let old = h.batch.cropDraft?.id
        await h.batch.replace(); XCTAssertEqual(h.batch.cropDraft?.id, old); XCTAssertTrue(h.batch.failed)
        h.batch.cancel(); XCTAssertNil(h.batch.cropDraft); XCTAssertEqual(h.batch.remainingCount, 0)
    }
    func testPickerBoundAndOrderedConfigurationWithoutPresentation() async throws {
        var limit = 0
        let picker = RetainedNativeImagePicker(enabled: true, present: { controller in
            let value = controller as! PHPickerViewController
            limit = value.configuration.selectionLimit
            XCTAssertEqual(value.configuration.selection, .ordered)
            return false
        }, dismiss: {})
        do { _ = try await picker.selectBatch(limit: 2); XCTFail() } catch { }
        XCTAssertEqual(limit, 2)
        do { _ = try await picker.selectBatch(limit: 10); XCTFail() } catch { }
        XCTAssertEqual(limit, 2)
    }

}
