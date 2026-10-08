import Foundation
import XCTest
@testable import QuestifyCore

@MainActor final class SquarePostLocalMediaSelectionTests: XCTestCase {
    private func scope(account: Int = 7, namespace: String = "local-fixture", epoch: UInt64 = 1,
                       draft: String = "local-draft", lane: SquareWorkspaceLane = .communityV1) throws -> SquarePostLocalMediaScope {
        try .init(session: .init(accountID: account, namespace: namespace, epoch: epoch), draftID: draft, lane: lane)
    }
    private func policy(mixed: Bool = true) throws -> SquarePostLocalMediaPolicy {
        // Synthetic limits only. They are unrelated to server policy or publication rights.
        try .init(mimeTypes: [.image: ["image/png"], .video: ["video/mp4"]], maximumItems: 4,
                  maximumImages: 4, maximumVideos: 4, allowsMixed: mixed, maximumImageBytes: 10,
                  maximumVideoBytes: 10, maximumTotalBytes: 40, maximumVideoDurationMilliseconds: 100)
    }
    private func model() throws -> SquarePostLocalMediaSelection { try .init(scope: scope(), policy: policy()) }
    private func evidence(_ input: SquarePostLocalMediaByteInspection, text: String = "abc") throws -> SquarePostLocalMediaByteEvidence {
        var input = input; let bytes = Data(text.utf8); try input.append(bytes)
        let token = input.token
        return try input.finish(.init(reference: token.reference, kind: token.kind,
            mimeType: token.kind == .image ? "image/png" : "video/mp4", reportedByteCount: Int64(bytes.count),
            width: 1, height: 1, durationMilliseconds: token.kind == .video ? 10 : nil))
    }
    func testSelectionPreservesOrderAndRepeatedSourceWithSeparateItemIdentity() throws {
        var value = try model(); let source = SquarePostLocalMediaReference()
        let first = try value.append(reference: source, kind: .image), middle = try value.append(reference: .init(), kind: .video)
        let last = try value.append(reference: source, kind: .image)
        XCTAssertEqual(value.items.map(\.id), [first, middle, last]); XCTAssertNotEqual(first, last)
        XCTAssertEqual(value.items[0].reference, value.items[2].reference)
        XCTAssertEqual(value.snapshot.assessment, .inspectionPending)
    }
    func testReorderAndInterleavedChecksBindToIDsRatherThanOldOffsets() throws {
        var value = try model(); let a = try value.append(reference: .init(), kind: .image), b = try value.append(reference: .init(), kind: .video)
        let first = try value.beginInspection(a), second = try value.beginInspection(b), preview = value.snapshot
        try value.reorder([b, a]); XCTAssertFalse(value.isCurrent(preview))
        let ea = try evidence(first, text: "first"), eb = try evidence(second, text: "second")
        XCTAssertTrue(value.complete(ea)); XCTAssertEqual(value.items[1].phase, .bytesBoundMetadata(ea))
        XCTAssertEqual(value.items[0].phase, .inspecting(second.token))
        XCTAssertTrue(value.complete(eb)); XCTAssertEqual(value.items[0].phase, .bytesBoundMetadata(eb))
        XCTAssertEqual(value.snapshot.assessment, .metadataWithinPolicyAwaitingAppDecode)
    }
    func testDeleteAndReselectSameSourceCannotReceiveRemovedAttempt() throws {
        var value = try model(); let source = SquarePostLocalMediaReference(), oldID = try value.append(reference: source, kind: .video)
        let old = try value.beginInspection(oldID); XCTAssertEqual(value.remove(oldID), [source])
        let newID = try value.append(reference: source, kind: .video); XCTAssertNotEqual(newID, oldID)
        let before = value.snapshot
        XCTAssertFalse(value.complete(try evidence(old))); XCTAssertFalse(value.fail(old.token))
        XCTAssertEqual(value.snapshot, before); XCTAssertEqual(value.items[0].phase, .selected)
    }
    func testEqualReplacementAndSourceVersionABARetireOldAttempt() throws {
        for changedVersion in [false, true] {
            var value = try model(); let source = SquarePostLocalMediaReference(), id = try value.append(reference: source, kind: .image)
            let old = try value.beginInspection(id)
            if changedVersion { try value.replace(id, reference: .init(id: source.id), kind: .image) }
            try value.replace(id, reference: source, kind: .image)
            let before = value.snapshot; XCTAssertFalse(value.complete(try evidence(old))); XCTAssertEqual(value.snapshot, before)
            let fresh = try value.beginInspection(id); XCTAssertTrue(value.complete(try evidence(fresh)))
        }
    }
    func testRetryAndCancellationNeverAcceptOldCompletionsOrOldFailure() throws {
        var value = try model(); let id = try value.append(reference: .init(), kind: .video)
        let old = try value.beginInspection(id); XCTAssertTrue(value.cancelInspection(old.token))
        let next = try value.beginInspection(id); let before = value.snapshot
        XCTAssertFalse(value.cancelInspection(old.token)); XCTAssertFalse(value.fail(old.token)); XCTAssertFalse(value.complete(try evidence(old)))
        XCTAssertEqual(value.snapshot, before)
        let result = try evidence(next); XCTAssertTrue(value.complete(result)); XCTAssertFalse(value.complete(result))
        XCTAssertEqual(value.items[0].phase, .bytesBoundMetadata(result))
    }
    func testAllSquareScopeChangesRejectOldBytesAndReleaseOnlyLocalReferences() throws {
        let scopes = [try scope(account: 8), try scope(namespace: "other"), try scope(epoch: 2), try scope(draft: "other-draft"), try scope(lane: .legacy), try scope()]
        for replacement in scopes {
            var value = try model(); let source = SquarePostLocalMediaReference(), id = try value.append(reference: source, kind: .image)
            let old = try value.beginInspection(id)
            XCTAssertEqual(value.replaceScope(replacement), [source]); XCTAssertEqual(value.scope, replacement); XCTAssertNil(value.policy)
            XCTAssertFalse(value.complete(try evidence(old))); XCTAssertTrue(value.items.isEmpty)
            try value.append(reference: source, kind: .image); XCTAssertEqual(value.snapshot.assessment, .policyUnavailable)
        }
    }
    func testDifferentOwnerWithEqualScopeCannotConsumeAnotherOwnersEvidence() throws {
        var first = try model(), second = try model(); let source = SquarePostLocalMediaReference()
        let id = try first.append(reference: source, kind: .image); try second.append(reference: source, kind: .image)
        let proof = try evidence(first.beginInspection(id)), before = second.snapshot
        XCTAssertFalse(second.complete(proof)); XCTAssertEqual(second.snapshot, before); XCTAssertTrue(first.complete(proof))
    }
    func testPolicyChangeInvalidatesPreviewAndPendingCheckButPreservesBoundDescriptions() throws {
        var value = try model(); let image = try value.append(reference: .init(), kind: .image)
        let inspection = try value.beginInspection(image), boundEvidence = try evidence(inspection)
        XCTAssertTrue(value.complete(boundEvidence))
        let bound = value.items[0]
        let video = try value.append(reference: .init(), kind: .video), old = try value.beginInspection(video), before = value.snapshot
        value.updatePolicy(nil); XCTAssertFalse(value.isCurrent(before)); XCTAssertEqual(value.items[0], bound)
        XCTAssertEqual(value.snapshot.assessment, .policyUnavailable); XCTAssertFalse(value.complete(try evidence(old)))
        value.updatePolicy(try policy(mixed: false)); XCTAssertEqual(value.snapshot.assessment, .rejected(.mixedKinds))
        value.remove(video); XCTAssertEqual(value.snapshot.assessment, .metadataWithinPolicyAwaitingAppDecode)
    }
    func testLastRepeatedReferenceOnlyIsReportedForLocalCleanup() throws {
        var value = try model(); let source = SquarePostLocalMediaReference()
        let a = try value.append(reference: source, kind: .image), b = try value.append(reference: source, kind: .image)
        XCTAssertTrue(value.remove(a).isEmpty); XCTAssertEqual(value.remove(b), [source]); XCTAssertTrue(value.remove(b).isEmpty)
        try value.append(reference: source, kind: .image); try value.append(reference: source, kind: .image)
        XCTAssertEqual(value.clear(), [source]); XCTAssertTrue(value.clear().isEmpty)
    }
    func testBackgroundOrReturnInvalidationNeedsNewScopeLeaseAndNewInspection() throws {
        let value = try model(), source = SquarePostLocalMediaReference()
        let id = try value.append(reference: source, kind: .video), old = try value.beginInspection(id), before = value.snapshot
        value.invalidate(); XCTAssertFalse(value.isCurrent(before)); XCTAssertEqual(value.snapshot.assessment, .closed)
        XCTAssertThrowsError(try value.append(reference: .init(), kind: .image))
        // Finish the late attempt once; replay its proof to exercise each selection fence.
        let staleEvidence = try evidence(old), closed = value.snapshot
        XCTAssertFalse(value.complete(staleEvidence)); XCTAssertEqual(value.snapshot, closed)
        XCTAssertThrowsError(try evidence(old)) { XCTAssertEqual($0 as? SquarePostLocalMediaIssue, .finished) }
        XCTAssertEqual(value.snapshot, closed)
        value.replaceScope(try scope(), policy: try policy()); let reopened = value.snapshot
        XCTAssertFalse(value.complete(staleEvidence)); XCTAssertEqual(value.snapshot, reopened)
        XCTAssertEqual(value.snapshot.assessment, .empty)
        let newID = try value.append(reference: source, kind: .video), fresh = try value.beginInspection(newID)
        XCTAssertEqual(fresh.token.scope, old.token.scope); XCTAssertNotEqual(fresh.token.lease, old.token.lease)
        let inspecting = value.snapshot
        XCTAssertFalse(value.complete(staleEvidence)); XCTAssertEqual(value.snapshot, inspecting)
        XCTAssertTrue(value.complete(try evidence(fresh)))
        XCTAssertEqual(value.snapshot.assessment, .metadataWithinPolicyAwaitingAppDecode)
    }
    func testInvalidReorderIsAtomicAndOldSnapshotNeverBecomesCurrentAgain() throws {
        var value = try model(); let a = try value.append(reference: .init(), kind: .image), b = try value.append(reference: .init(), kind: .image), before = value.snapshot
        for invalid in [[a], [a, a], [a, UUID()]] {
            XCTAssertThrowsError(try value.reorder(invalid)); XCTAssertEqual(value.snapshot, before)
        }
        try value.reorder([b, a]); try value.reorder([a, b])
        XCTAssertEqual(value.items.map(\.id), [a, b]); XCTAssertFalse(value.isCurrent(before))
    }
    func testInspectionFailureRequiresExplicitNewAttemptWithoutRemovingTheItem() throws {
        var value = try model(); let id = try value.append(reference: .init(), kind: .image), attempt = try value.beginInspection(id)
        XCTAssertTrue(value.fail(attempt.token)); XCTAssertEqual(value.snapshot.assessment, .rejected(.inspectionFailed))
        XCTAssertEqual(value.items.count, 1); XCTAssertFalse(value.complete(try evidence(attempt)))
        let next = try value.beginInspection(id); XCTAssertNotEqual(next.token.id, attempt.token.id)
        XCTAssertTrue(value.complete(try evidence(next))); XCTAssertEqual(value.snapshot.assessment, .metadataWithinPolicyAwaitingAppDecode)
    }
    func testSameReferenceVersionRejectsChangedBytesUntilNewVersionIsSelected() throws {
        var value = try model(); let source = SquarePostLocalMediaReference(), id = try value.append(reference: source, kind: .image)
        let first = try value.beginInspection(id); XCTAssertTrue(value.complete(try evidence(first, text: "abc")))
        let changed = try value.beginInspection(id); XCTAssertFalse(value.complete(try evidence(changed, text: "def")))
        XCTAssertEqual(value.snapshot.assessment, .rejected(.sourceBytesChanged))
        value.clear()
        let repeated = try value.append(reference: source, kind: .image), repeatedAttempt = try value.beginInspection(repeated)
        XCTAssertFalse(value.complete(try evidence(repeatedAttempt, text: "def")), "Clearing cannot reuse an unchanged file version for different bytes")
        try value.replace(repeated, reference: .init(id: source.id), kind: .image)
        let current = try value.beginInspection(repeated); XCTAssertTrue(value.complete(try evidence(current, text: "def")))
        XCTAssertEqual(value.snapshot.assessment, .metadataWithinPolicyAwaitingAppDecode)
    }
    func testRetainedOwnerReferenceCannotRestoreAnEarlierSelectionState() throws {
        let value = try model(), retainedOwner = value, source = SquarePostLocalMediaReference()
        let id = try value.append(reference: source, kind: .image), pending = try value.beginInspection(id)
        let captured = value.snapshot; value.remove(id)
        XCTAssertTrue(value === retainedOwner); XCTAssertTrue(retainedOwner.items.isEmpty)
        // The retained wrapper shares one consumed stream, while evidence can be replayed.
        let staleEvidence = try evidence(pending), removed = value.snapshot
        XCTAssertFalse(retainedOwner.isCurrent(captured)); XCTAssertFalse(retainedOwner.complete(staleEvidence))
        XCTAssertEqual(value.snapshot, removed)
        value.invalidate(); let closed = value.snapshot
        XCTAssertFalse(retainedOwner.complete(staleEvidence)); XCTAssertEqual(value.snapshot, closed)
        XCTAssertThrowsError(try evidence(pending)) { XCTAssertEqual($0 as? SquarePostLocalMediaIssue, .finished) }
        XCTAssertEqual(value.snapshot, closed)
        retainedOwner.replaceScope(try scope(), policy: try policy())
        let newID = try retainedOwner.append(reference: source, kind: .image), fresh = try retainedOwner.beginInspection(newID)
        XCTAssertEqual(fresh.token.scope, pending.token.scope); XCTAssertNotEqual(fresh.token.lease, pending.token.lease)
        let inspecting = value.snapshot
        XCTAssertFalse(retainedOwner.complete(staleEvidence)); XCTAssertEqual(value.snapshot, inspecting)
        XCTAssertTrue(value.complete(try evidence(fresh)))
        XCTAssertEqual(retainedOwner.snapshot.assessment, .metadataWithinPolicyAwaitingAppDecode)
    }
}
