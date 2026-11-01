import Foundation
import XCTest
@testable import QuestifyCore

@MainActor
final class ClubPostImageUploadTests: XCTestCase {
    private let baseURL = URL(string: "https://api.example.com")!
    private let approvedOrigins: Set<String> = ["https://cdn.example.com"]

    private func makeValidJPEG(seed: UInt8 = 1) throws -> RetainedSelectedImage {
        try RetainedSelectedImage(
            jpeg: Data([255, 216, 255, 224, seed, 255, 217]),
            width: 120,
            height: 90
        )
    }

    func testReferenceValidatorRejectsFixtureInvalidDelimitersAndUnapprovedOrigins() async throws {
        // Synthetic fixture URLs are strictly rejected
        let syntheticList = try await ClubCommunitySyntheticImages().uploadSynthetic([Data([1])])
        let synthetic = try XCTUnwrap(syntheticList.first)
        XCTAssertFalse(
            ClubPostImageReferenceValidator.isValidReference(
                synthetic,
                approvedOrigins: approvedOrigins
            )
        )
        XCTAssertThrowsError(
            try ClubPostImageUploadApproval(
                baseURL: baseURL,
                namespace: "cn.prod",
                accountID: 7,
                clubID: 3,
                approvedOrigins: ["https://fixture.invalid"]
            )
        )

        // Delimiters `;` and `,` are rejected
        XCTAssertFalse(
            ClubPostImageReferenceValidator.isValidReference(
                "https://cdn.example.com/a.jpg;https://cdn.example.com/b.jpg",
                approvedOrigins: approvedOrigins
            )
        )
        XCTAssertFalse(
            ClubPostImageReferenceValidator.isValidReference(
                "https://cdn.example.com/a.jpg,b.jpg",
                approvedOrigins: approvedOrigins
            )
        )

        // Unapproved origin or non-HTTPS rejected
        XCTAssertFalse(
            ClubPostImageReferenceValidator.isValidReference(
                "https://untrusted.example.org/a.jpg",
                approvedOrigins: approvedOrigins
            )
        )
        XCTAssertFalse(
            ClubPostImageReferenceValidator.isValidReference(
                "http://cdn.example.com/a.jpg",
                approvedOrigins: approvedOrigins
            )
        )

        // Approved HTTPS reference accepted
        XCTAssertTrue(
            ClubPostImageReferenceValidator.isValidReference(
                "https://cdn.example.com/club/post-1.jpg",
                approvedOrigins: approvedOrigins
            )
        )
    }

    func testUploadClientEnforcesClubSpecificApprovalAndRejectsContextSwitchMidUpload() async throws {
        var liveContext = try ClubPostImageUploadContext(
            accountID: 7,
            epoch: 1,
            namespace: "cn.prod",
            clubID: 3
        )
        var liveApproval: ClubPostImageUploadApproval? = nil
        var sentCount = 0

        let transport = SpyUploadHTTPTransport { request in
            sentCount += 1
            XCTAssertEqual(request.url?.path, "/api/common/uploadOSS")
            let bodyString = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            XCTAssertTrue(bodyString.contains("club_post_image"))
            return (Data(#"{"code":200,"url":"https://cdn.example.com/club/uploaded-1.jpg"}"#.utf8), 200)
        }

        let client = ClubPostImageUploadClient(
            configuration: try APIConfiguration(baseURL: baseURL),
            transport: transport,
            currentContext: { liveContext },
            currentToken: { "tok-7" },
            currentApproval: { liveApproval }
        )

        let image = try makeValidJPEG()

        // 1. Missing approval -> fails closed with 0 HTTP requests
        XCTAssertFalse(client.isConfigured(for: liveContext))
        do {
            _ = try await client.upload(image, attemptID: UUID(), context: liveContext)
            XCTFail("Expected upload to fail when approval is nil")
        } catch let error as ClubPostImageUploadFailure {
            XCTAssertEqual(error, .notConfigured)
        }
        XCTAssertEqual(sentCount, 0)

        // 2. Approval for a different club (clubID: 99) -> still fails closed for clubID: 3
        liveApproval = try ClubPostImageUploadApproval(
            baseURL: baseURL,
            namespace: "cn.prod",
            accountID: 7,
            clubID: 99,
            approvedOrigins: approvedOrigins,
            nativePicker: true
        )
        XCTAssertFalse(client.isConfigured(for: liveContext))
        XCTAssertEqual(sentCount, 0)

        // 3. Matching club approval -> succeeds and verifies origin
        liveApproval = try ClubPostImageUploadApproval(
            baseURL: baseURL,
            namespace: "cn.prod",
            accountID: 7,
            clubID: 3,
            approvedOrigins: approvedOrigins,
            nativePicker: true
        )
        XCTAssertTrue(client.isConfigured(for: liveContext))
        let attemptID = UUID()
        let uploaded = try await client.upload(image, attemptID: attemptID, context: liveContext)
        XCTAssertEqual(uploaded.reference, "https://cdn.example.com/club/uploaded-1.jpg")
        XCTAssertEqual(client.permittedReference(uploaded, for: liveContext), "https://cdn.example.com/club/uploaded-1.jpg")
        XCTAssertEqual(sentCount, 1)

        // 4. Reusing the same attemptID fails closed with 0 extra HTTP requests
        do {
            _ = try await client.upload(image, attemptID: attemptID, context: liveContext)
            XCTFail("Expected duplicate attemptID to be rejected")
        } catch let error as ClubPostImageUploadFailure {
            XCTAssertEqual(error, .alreadyAttempted)
        }
        XCTAssertEqual(sentCount, 1)

        // 5. Context switch mid-upload drops response with .changedContext
        let switchingTransport = SpyUploadHTTPTransport { _ in
            liveContext = try! ClubPostImageUploadContext(
                accountID: 8,
                epoch: 2,
                namespace: "cn.prod",
                clubID: 3
            )
            return (Data(#"{"code":200,"url":"https://cdn.example.com/club/uploaded-2.jpg"}"#.utf8), 200)
        }
        let switchingClient = ClubPostImageUploadClient(
            configuration: try APIConfiguration(baseURL: baseURL),
            transport: switchingTransport,
            currentContext: { liveContext },
            currentToken: { "tok-7" },
            currentApproval: { liveApproval }
        )
        liveContext = try ClubPostImageUploadContext(
            accountID: 7,
            epoch: 1,
            namespace: "cn.prod",
            clubID: 3
        )
        do {
            _ = try await switchingClient.upload(image, attemptID: UUID(), context: liveContext)
            XCTFail("Expected context switch mid-upload to fail with .changedContext")
        } catch let error as ClubPostImageUploadFailure {
            XCTAssertEqual(error, .changedContext)
        }
    }

    func testDraftControllerRetainsLocalCandidateWhenUploadUnconfiguredAndNeverAutoSubmits() async throws {
        var liveContext: ClubPostImageUploadContext? = try ClubPostImageUploadContext(
            accountID: 7,
            epoch: 1,
            namespace: "cn.prod",
            clubID: 3
        )
        let controller = ClubPostImageDraftController(
            uploader: ClubPostImageDisabledUploader(),
            currentContext: { liveContext }
        )
        controller.bind(context: liveContext, initialReferences: ["https://cdn.example.com/existing.jpg"])
        XCTAssertEqual(controller.uploadedReferences, ["https://cdn.example.com/existing.jpg"])

        let candidate = try makeValidJPEG(seed: 2)
        let staged = await controller.stageSelectedImage(candidate)
        XCTAssertTrue(staged)
        XCTAssertEqual(controller.localCandidates, [candidate])
        XCTAssertEqual(controller.statusKey, "club.community.imageUploadUnconfiguredLocalDraft")
        XCTAssertFalse(controller.didAutoSubmit)

        // Remove local candidate
        controller.removeLocalCandidate(id: candidate.id)
        XCTAssertTrue(controller.localCandidates.isEmpty)

        // Account/epoch switch invalidates draft state immediately
        liveContext = try ClubPostImageUploadContext(
            accountID: 9,
            epoch: 2,
            namespace: "cn.prod",
            clubID: 3
        )
        XCTAssertNil(controller.validateCurrentContext())
        XCTAssertTrue(controller.uploadedReferences.isEmpty)
        XCTAssertTrue(controller.localCandidates.isEmpty)
    }

    func testDraftControllerReplaceCancelAndCompositionRouteAdmission() async throws {
        let liveContext = try ClubPostImageUploadContext(
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
        var uploadCounter = 0
        var seenRoute: ClubPostImageUploadCompositionRoute?
        let transport = SpyUploadHTTPTransport { request in
            seenRoute = ClubPostImageUploadCompositionRoute(request: request, baseURL: self.baseURL)
            uploadCounter += 1
            return (Data(#"{"code":200,"url":"https://cdn.example.com/club/replaced-\#(uploadCounter).jpg"}"#.utf8), 200)
        }
        let client = ClubPostImageUploadClient(
            configuration: try APIConfiguration(baseURL: baseURL),
            transport: transport,
            currentContext: { liveContext },
            currentToken: { "tok-7" },
            currentApproval: { approval }
        )
        let controller = ClubPostImageDraftController(
            uploader: client,
            currentContext: { liveContext }
        )
        controller.bind(
            context: liveContext,
            initialReferences: ["https://cdn.example.com/club/initial.jpg"]
        )

        // 1. Replace uploaded reference in place and verify route admission
        let replacementImage = try makeValidJPEG(seed: 11)
        let didReplace = await controller.replaceUploadedReference(at: 0, with: replacementImage)
        XCTAssertTrue(didReplace)
        XCTAssertNotNil(seenRoute)
        XCTAssertEqual(controller.uploadedReferences, ["https://cdn.example.com/club/replaced-1.jpg"])
        XCTAssertEqual(
            controller.previewsByReference["https://cdn.example.com/club/replaced-1.jpg"],
            replacementImage
        )
        XCTAssertFalse(controller.didAutoSubmit)

        // 2. Replace local candidate in place when uploader is unconfigured
        let localController = ClubPostImageDraftController(
            uploader: ClubPostImageDisabledUploader(),
            currentContext: { liveContext }
        )
        localController.bind(context: liveContext, initialReferences: [])
        let firstLocal = try makeValidJPEG(seed: 21)
        let secondLocal = try makeValidJPEG(seed: 22)
        _ = await localController.stageSelectedImage(firstLocal)
        let replacedLocal = localController.replaceLocalCandidate(id: firstLocal.id, with: secondLocal)
        XCTAssertTrue(replacedLocal)
        XCTAssertEqual(localController.localCandidates, [secondLocal])

        // 3. Cancel active upload clears uploading state and sets cancelled status
        localController.cancelCurrentUpload()
        XCTAssertFalse(localController.isUploading)
        XCTAssertEqual(localController.statusKey, "club.community.imageUploadCancelled")
        XCTAssertFalse(localController.didAutoSubmit)
    }
}

@MainActor
private final class SpyUploadHTTPTransport: HTTPTransport {
    let handler: (URLRequest) async throws -> (Data, Int)
    init(_ handler: @escaping (URLRequest) async throws -> (Data, Int)) {
        self.handler = handler
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        try await handler(request)
    }
}
