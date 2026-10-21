import Foundation
import UIKit
import XCTest
@testable import Questify

@MainActor
final class ClubPostImagePickerTests: XCTestCase {
    private let baseURL = URL(string: "https://api.example.com")!
    private let approvedOrigins: Set<String> = ["https://cdn.example.com"]

    private func makeSanitizedImage(width: Int = 80, height: Int = 60) throws -> RetainedSelectedImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return try RetainedImageSanitizer.sanitize(XCTUnwrap(image.jpegData(compressionQuality: 0.9)))
    }

    func testComposerBridgeSelectPreviewRemovePreservesTextAndNeverAutoSubmits() async throws {
        let selected = try makeSanitizedImage()
        let picker = StubClubPostImagePicker(image: selected)
        let uploadContext = try ClubPostImageUploadContext(
            accountID: 7,
            epoch: 1,
            namespace: "cn.prod",
            clubID: 3
        )
        let context = ClubPostImagePickerContext(
            makePicker: { picker },
            uploader: ClubPostImageDisabledUploader(),
            currentUploadContext: { clubID, postID in
                try? ClubPostImageUploadContext(
                    accountID: uploadContext.accountID,
                    epoch: uploadContext.epoch,
                    namespace: uploadContext.namespace,
                    clubID: clubID,
                    postID: postID
                )
            }
        )

        let bridge = ClubPostImageComposerBridge(context: context, clubID: 3, postID: nil)
        var composerText = "Draft club post text before opening picker"
        bridge.bind(initialReferences: [])

        let references = await bridge.selectAndStageImage()
        XCTAssertTrue(references.isEmpty)
        XCTAssertEqual(bridge.draft.localCandidates, [selected])
        XCTAssertEqual(bridge.draft.statusKey, "club.community.imageUploadUnconfiguredLocalDraft")
        XCTAssertEqual(composerText, "Draft club post text before opening picker")
        XCTAssertFalse(bridge.draft.didAutoSubmit)

        // Preview and close preserve both text and candidate
        bridge.openPreview(selected)
        XCTAssertEqual(bridge.previewingCandidate, selected)
        bridge.closePreview()
        XCTAssertNil(bridge.previewingCandidate)
        XCTAssertEqual(composerText, "Draft club post text before opening picker")

        // Removing local candidate clears preview and leaves text untouched
        bridge.removeLocalCandidate(id: selected.id)
        XCTAssertTrue(bridge.draft.localCandidates.isEmpty)
        composerText += " - edited"
        XCTAssertEqual(composerText, "Draft club post text before opening picker - edited")
    }

    func testComposerBridgeWithApprovedUploaderStagesVerifiedReferenceAndDropsLateContextSwitch() async throws {
        let selected = try makeSanitizedImage()
        let picker = StubClubPostImagePicker(image: selected)
        var liveContext = try ClubPostImageUploadContext(
            accountID: 7,
            epoch: 1,
            namespace: "cn.prod",
            clubID: 3
        )
        let approval = try ClubPostImageUploadApproval(
            baseURL: baseURL,
            namespace: "cn.prod",
            accountID: 7,
            clubID: 3,
            approvedOrigins: approvedOrigins,
            nativePicker: true
        )
        var switchContextDuringUpload = false

        let transport = StubPickerHTTPTransport { _ in
            if switchContextDuringUpload {
                liveContext = try! ClubPostImageUploadContext(
                    accountID: 88,
                    epoch: 2,
                    namespace: "cn.prod",
                    clubID: 3
                )
            }
            return (Data(#"{"code":200,"url":"https://cdn.example.com/club/post-img-1.jpg"}"#.utf8), 200)
        }
        let uploader = ClubPostImageUploadClient(
            configuration: try APIConfiguration(baseURL: baseURL),
            transport: transport,
            currentContext: { liveContext },
            currentToken: { "tok-7" },
            currentApproval: { approval }
        )
        let context = ClubPostImagePickerContext(
            makePicker: { picker },
            uploader: uploader,
            currentUploadContext: { _, _ in liveContext }
        )

        let bridge = ClubPostImageComposerBridge(context: context, clubID: 3, postID: nil)
        bridge.bind(initialReferences: [])

        // 1. Approved upload appends verified reference and stores local preview
        let uploadedRefs = await bridge.selectAndStageImage()
        XCTAssertEqual(uploadedRefs, ["https://cdn.example.com/club/post-img-1.jpg"])
        XCTAssertEqual(
            bridge.draft.previewsByReference["https://cdn.example.com/club/post-img-1.jpg"],
            selected
        )
        XCTAssertFalse(bridge.draft.didAutoSubmit)

        // 2. Remove uploaded reference
        let afterRemove = bridge.removeUploadedReference(at: 0)
        XCTAssertTrue(afterRemove.isEmpty)

        // 3. Context switch mid-upload drops late upload completion and invalidates draft
        switchContextDuringUpload = true
        let afterSwitch = await bridge.selectAndStageImage()
        XCTAssertTrue(afterSwitch.isEmpty)
        XCTAssertTrue(bridge.draft.uploadedReferences.isEmpty)
        XCTAssertTrue(bridge.draft.localCandidates.isEmpty)
    }
}

@MainActor
private final class StubClubPostImagePicker: ClubPostImagePicking {
    var canSelect: Bool = true
    var image: RetainedSelectedImage?
    private(set) var cancelled = false

    init(image: RetainedSelectedImage?) {
        self.image = image
    }

    func select() async throws -> RetainedSelectedImage? {
        cancelled ? nil : image
    }

    func cancel() {
        cancelled = true
    }
}

@MainActor
private final class StubPickerHTTPTransport: HTTPTransport {
    let handler: (URLRequest) async throws -> (Data, Int)
    init(_ handler: @escaping (URLRequest) async throws -> (Data, Int)) {
        self.handler = handler
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        try await handler(request)
    }
}
