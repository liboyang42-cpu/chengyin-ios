import Foundation
import XCTest
@testable import QuestifyCore

@MainActor final class SquarePostLocalMediaContractsTests: XCTestCase {
    // Artificial fixture limits only; these numbers are not a product or backend policy.
    private func policy(items: Int? = 3, images: Int? = 3, videos: Int? = 2, mixed: Bool? = true,
                        imageBytes: Int64? = 8, videoBytes: Int64? = 8, total: Int64? = 16,
                        duration: Int64? = 20,
                        mimes: [SquarePostLocalMediaKind: Set<String>] = [.image: ["image/png"], .video: ["video/mp4"]]) throws -> SquarePostLocalMediaPolicy {
        try .init(mimeTypes: mimes, maximumItems: items, maximumImages: images, maximumVideos: videos,
                  allowsMixed: mixed, maximumImageBytes: imageBytes, maximumVideoBytes: videoBytes,
                  maximumTotalBytes: total, maximumVideoDurationMilliseconds: duration)
    }
    private func selection(_ policy: SquarePostLocalMediaPolicy? = nil) throws -> SquarePostLocalMediaSelection {
        try .init(scope: .init(session: .init(accountID: 7, namespace: "synthetic-local", epoch: 1), draftID: "synthetic-draft", lane: .communityV1), policy: policy)
    }
    private func description(_ token: SquarePostLocalMediaInspectionToken, bytes: Int64 = 3, mime: String? = nil,
                             width: Int = 1, height: Int = 1, duration: Int64? = nil) -> SquarePostLocalMediaDescription {
        .init(reference: token.reference, kind: token.kind, mimeType: mime ?? (token.kind == .image ? "image/png" : "video/mp4"),
              reportedByteCount: bytes, width: width, height: height, durationMilliseconds: duration)
    }
    @discardableResult private func add(_ kind: SquarePostLocalMediaKind, to model: inout SquarePostLocalMediaSelection,
                                        bytes: Data = Data("abc".utf8), duration: Int64? = nil, mime: String? = nil) throws -> UUID {
        let id = try model.append(reference: .init(), kind: kind)
        var inspection = try model.beginInspection(id); try inspection.append(bytes)
        let value = try inspection.finish(description(inspection.token, bytes: Int64(bytes.count), mime: mime, duration: duration))
        XCTAssertTrue(model.complete(value)); XCTAssertFalse(value.appDecodingPerformed); return id
    }
    func testActualChunksDetermineCountAndDigestWithoutClaimingMediaDecoding() throws {
        var model = try selection(policy())
        let id = try model.append(reference: .init(), kind: .video)
        var inspection = try model.beginInspection(id)
        try inspection.append(Data("a".utf8)); try inspection.append(Data()); try inspection.append(Data("bc".utf8))
        var sibling = inspection
        let evidence = try inspection.finish(description(inspection.token, duration: 10))
        XCTAssertEqual(evidence.byteCount, 3)
        XCTAssertEqual(evidence.sha256, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertFalse(evidence.appDecodingPerformed, "abc is not a video; this layer cannot call it decoded")
        XCTAssertTrue(model.complete(evidence)); XCTAssertEqual(model.snapshot.assessment, .metadataWithinPolicyAwaitingAppDecode)
        XCTAssertThrowsError(try inspection.append(Data([4]))); XCTAssertThrowsError(try inspection.finish(description(inspection.token, duration: 10)))
        XCTAssertThrowsError(try sibling.finish(description(sibling.token, duration: 10))) { XCTAssertEqual($0 as? SquarePostLocalMediaIssue, .finished) }
    }
    func testDescriptionWithoutBytesAndFalseByteSizeCannotMintEvidence() throws {
        var model = try selection(policy()); let id = try model.append(reference: .init(), kind: .image)
        var empty = try model.beginInspection(id)
        XCTAssertThrowsError(try empty.finish(description(empty.token))) { XCTAssertEqual($0 as? SquarePostLocalMediaIssue, .noBytes) }
        XCTAssertEqual(model.snapshot.assessment, .inspectionPending)
        var mismatch = try model.beginInspection(id); try mismatch.append(Data("abc".utf8))
        XCTAssertThrowsError(try mismatch.finish(description(mismatch.token, bytes: 2))) { XCTAssertEqual($0 as? SquarePostLocalMediaIssue, .byteCountMismatch) }
        XCTAssertThrowsError(try mismatch.finish(description(mismatch.token)))
    }
    func testEvidenceRequiresExactReferenceVersionAndExplicitKind() throws {
        for wrongKind in [false, true] {
            var model = try selection(policy()); let id = try model.append(reference: .init(), kind: .image)
            var inspection = try model.beginInspection(id); try inspection.append(Data("abc".utf8))
            let token = inspection.token
            let reference = wrongKind ? token.reference : SquarePostLocalMediaReference(id: token.reference.id, version: UUID())
            let value = SquarePostLocalMediaDescription(reference: reference, kind: wrongKind ? .video : .image,
                mimeType: wrongKind ? "video/mp4" : "image/png", reportedByteCount: 3, width: 1, height: 1, durationMilliseconds: wrongKind ? 10 : nil)
            XCTAssertThrowsError(try inspection.finish(value)) { XCTAssertEqual($0 as? SquarePostLocalMediaIssue, wrongKind ? .wrongKind : .wrongReference) }
        }
    }
    func testMIMEAndDimensionAndDurationDescriptionsFailClosed() throws {
        for mode in 0..<8 {
            var model = try selection(policy()); let kind: SquarePostLocalMediaKind = mode >= 5 ? .video : .image
            let id = try model.append(reference: .init(), kind: kind); var inspection = try model.beginInspection(id); try inspection.append(Data("abc".utf8))
            let value = description(inspection.token, mime: mode == 0 ? "video/mp4" : mode == 1 ? "image/png;parameter=x" : nil,
                width: mode == 2 ? 0 : mode == 3 ? Int.max : 1, height: mode == 3 ? Int.max : 1,
                duration: mode == 4 ? 1 : mode == 5 ? nil : mode == 6 ? 0 : mode == 7 ? -1 : nil)
            XCTAssertThrowsError(try inspection.finish(value)) { XCTAssertEqual($0 as? SquarePostLocalMediaIssue, .invalidMetadata) }
        }
    }
    func testOverLimitStreamCannotReturnAcceptedPrefixAfterAnError() throws {
        var model = try selection(policy(imageBytes: 2)); let id = try model.append(reference: .init(), kind: .image)
        var inspection = try model.beginInspection(id); try inspection.append(Data("ab".utf8))
        XCTAssertThrowsError(try inspection.append(Data("c".utf8))) { XCTAssertEqual($0 as? SquarePostLocalMediaIssue, .byteLimit) }
        XCTAssertThrowsError(try inspection.finish(description(inspection.token, bytes: 2))) { XCTAssertEqual($0 as? SquarePostLocalMediaIssue, .byteLimit) }
        XCTAssertEqual(model.items.count, 1); XCTAssertEqual(model.snapshot.assessment, .inspectionPending)
    }
    func testUnknownOrIncompletePolicyNeverApprovesSuppliedMetadata() throws {
        var noPolicy = try selection(); try add(.image, to: &noPolicy)
        XCTAssertEqual(noPolicy.snapshot.assessment, .policyUnavailable)
        for p in [try policy(items: nil), try policy(total: nil), try policy(videoBytes: nil), try policy(duration: nil)] {
            var model = try selection(p); try add(.video, to: &model, duration: 10)
            XCTAssertEqual(model.snapshot.assessment, .policyUnavailable)
        }
        var mixingUnknown = try selection(policy(mixed: nil)); try add(.image, to: &mixingUnknown); try add(.video, to: &mixingUnknown, duration: 10)
        XCTAssertEqual(mixingUnknown.snapshot.assessment, .policyUnavailable)
    }
    func testInjectedCountsMixingAndFormatPoliciesPreserveAllSelectedItems() throws {
        let cases: [(SquarePostLocalMediaPolicy, SquarePostLocalMediaIssue)] = [
            (try policy(items: 1), .itemLimit), (try policy(images: 0), .imageLimit),
            (try policy(videos: 0), .videoLimit), (try policy(mixed: false), .mixedKinds),
            (try policy(mimes: [.image: ["image/png"]]), .kindNotAllowed),
            (try policy(mimes: [.image: ["image/jpeg"], .video: ["video/mp4"]]), .mimeNotAllowed)]
        for (p, issue) in cases {
            var model = try selection(p); try add(.image, to: &model); try add(.video, to: &model, duration: 10)
            XCTAssertEqual(model.items.count, 2); XCTAssertEqual(model.snapshot.assessment, .rejected(issue))
        }
    }
    func testByteAndDurationRulesUseInclusiveInjectedBoundariesAndInt64Extremes() throws {
        var model = try selection(policy(total: 6, duration: 10)); try add(.image, to: &model); try add(.video, to: &model, duration: 10)
        XCTAssertEqual(model.snapshot.assessment, .metadataWithinPolicyAwaitingAppDecode)
        model.updatePolicy(try policy(total: 5)); XCTAssertEqual(model.snapshot.assessment, .rejected(.byteLimit))
        model.updatePolicy(try policy(duration: 9)); XCTAssertEqual(model.snapshot.assessment, .rejected(.durationLimit))
        var extreme = try selection(policy()); try add(.video, to: &extreme, duration: Int64.max)
        XCTAssertEqual(extreme.snapshot.assessment, .rejected(.durationLimit))
        XCTAssertEqual(try SquarePostLocalMediaArithmetic.adding(Int64.max - 1, 1), Int64.max)
        XCTAssertThrowsError(try SquarePostLocalMediaArithmetic.adding(Int64.max, 1)) { XCTAssertEqual($0 as? SquarePostLocalMediaIssue, .byteCountOverflow) }
        XCTAssertThrowsError(try SquarePostLocalMediaArithmetic.adding(0, -1))
    }
    func testInvalidPoliciesAndScopesAreNotReinterpretedAsUnlimited() throws {
        XCTAssertThrowsError(try policy(items: -1)); XCTAssertThrowsError(try policy(videoBytes: 0)); XCTAssertThrowsError(try policy(duration: -1))
        XCTAssertThrowsError(try policy(mimes: [.image: ["video/mp4"]])); XCTAssertThrowsError(try policy(mimes: [.video: ["video/*"]]))
        let session = try SquareWorkspaceSession(accountID: 7, namespace: "synthetic", epoch: 1)
        XCTAssertThrowsError(try SquarePostLocalMediaScope(session: session, draftID: "  \n", lane: .legacy))
    }
    func testCopiedPrefixCannotMintEvidenceAfterOriginalAttemptExceedsLimit() throws {
        var model = try selection(policy(imageBytes: 2)); let id = try model.append(reference: .init(), kind: .image)
        var original = try model.beginInspection(id); try original.append(Data("ab".utf8))
        var copiedPrefix = original
        XCTAssertThrowsError(try original.append(Data("c".utf8))) { XCTAssertEqual($0 as? SquarePostLocalMediaIssue, .byteLimit) }
        XCTAssertThrowsError(try copiedPrefix.finish(description(copiedPrefix.token, bytes: 2))) { XCTAssertEqual($0 as? SquarePostLocalMediaIssue, .byteLimit) }
        XCTAssertThrowsError(try original.finish(description(original.token, bytes: 2))) { XCTAssertEqual($0 as? SquarePostLocalMediaIssue, .finished) }
        XCTAssertEqual(model.snapshot.assessment, .inspectionPending)
        XCTAssertTrue(model.fail(original.token, issue: .byteLimit)); XCTAssertEqual(model.snapshot.assessment, .rejected(.byteLimit))
        var retry = try model.beginInspection(id); try retry.append(Data("ab".utf8))
        let current = model.snapshot
        XCTAssertFalse(model.fail(original.token, issue: .byteLimit)); XCTAssertEqual(model.snapshot, current)
        XCTAssertTrue(model.complete(try retry.finish(description(retry.token, bytes: 2))))
        XCTAssertEqual(model.snapshot.assessment, .metadataWithinPolicyAwaitingAppDecode)
    }
    func testInspectionAliasesShareActualByteCountAndDigestBeforeOneFinish() throws {
        var model = try selection(policy(imageBytes: 4)); let id = try model.append(reference: .init(), kind: .image)
        var original = try model.beginInspection(id); try original.append(Data("a".utf8))
        var alias = original; try alias.append(Data("bc".utf8))
        let evidence = try original.finish(description(original.token, bytes: 3))
        XCTAssertEqual(evidence.byteCount, 3)
        XCTAssertEqual(evidence.sha256, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertThrowsError(try alias.append(Data("d".utf8))) { XCTAssertEqual($0 as? SquarePostLocalMediaIssue, .finished) }
        XCTAssertTrue(model.complete(evidence)); XCTAssertFalse(evidence.appDecodingPerformed)
    }
}
