import XCTest
@testable import QuestifyCore

@MainActor final class ApprovedTopicFrozenCoverBindingTests: XCTestCase {
    private func session() throws -> ProjectEditSession { try .init(accountID: 7, epoch: 1, storageNamespace: "frozen-cover-binding") }
    private func origin(_ session: ProjectEditSession) throws -> ApprovedTopicReleaseReadTarget {
        let ack = try ProjectEditBundleAcknowledgment.decode(.object(["topicId": .number(7901), "auditTaskId": .number(3301), "reviewState": .string("PENDING"), "published": .bool(true), "bundledTemplateIds": .array([.number(41)])]), expectedTopicID: nil)
        let pending = try ProjectEditPending(operationID: UUID(), ownerKey: session.ownerKey, identity: .init(), payload: ProjectEditContract.payload(ProjectEditSyntheticFixtures.draft(), topicID: nil, scope: .full), completedTopicID: 7901, serverAcknowledged: true, bundleAcknowledgment: ack)
        return try XCTUnwrap(ApprovedTopicReleaseReadTarget(pending: pending, session: session))
    }
    private func capture(_ edit: (inout [String: ProjectEditJSON]) -> Void = { _ in }) throws -> ApprovedTopicReviewCapture {
        var root = ApprovedTopicReviewSynthetic.captureFields().object!, summary = root["summary"]!.object!
        var cover = ApprovedTopicReviewSynthetic.selectedCoverFields(owner: 7, releaseBound: true).object!
        edit(&cover); summary["selectedCover"] = .object(cover); root["summary"] = .object(summary)
        return try .decode(.object(root), topicID: 7901, observedAuditTaskID: 3301)
    }
    private func preparation(_ edit: (inout [String: ProjectEditJSON]) -> Void = { _ in }) throws -> ApprovedTopicReleasePreparation {
        let envelope = try ApprovedTopicReleaseWire.envelope(ApprovedTopicReleaseSyntheticSource.preparationData(selectedCoverOwner: 7))
        var root = envelope["data"]!.object!; edit(&root)
        return try .decode(.object(root), topicID: 7901, auditTaskID: 3301)
    }
    func testExplicitFrozenBindingHasExactRoundTripButStillCarriesNoApprovalOrPlayerGrant() throws {
        let value = try capture(), cover = try XCTUnwrap(value.selectedCover)
        XCTAssertTrue(value.coverBindingAllowsReview); XCTAssertEqual(cover.binding, .frozenReleaseReplacement)
        XCTAssertEqual(cover.assetID, "11111111-1111-4111-8111-111111111111"); XCTAssertEqual(cover.selectionVersion, 9)
        XCTAssertEqual(cover.persistedFields.object?["publicPlayerReadable"], .bool(false))
        XCTAssertEqual(cover.persistedFields.object?["approvalProof"], .bool(false))
        XCTAssertEqual(try ApprovedTopicReviewCapture.decode(value.serializedFields(), topicID: 7901, observedAuditTaskID: 3301), value)
    }
    func testBindingWithoutPinnedRunContractOrWithPromotedFlagsFailsClosed() {
        for key in ["playerReadContract", "bindingState", "approvalProof", "publicPlayerReadable", "legacyImageBindingVerified"] {
            XCTAssertThrowsError(try capture { $0[key] = key == "playerReadContract" ? .string("PUBLIC_URL") : .bool(true) }, key)
        }
        XCTAssertThrowsError(try capture { $0.removeValue(forKey: "playerReadContract") })
        XCTAssertThrowsError(try capture { $0["bindingState"] = .string("AUTHOR_PREVIEW_ONLY") })
    }
    func testRealClientReviewUnknownRestoreUsesExactCapturedAssetAndOriginalRequest() async throws {
        let session = try session(), origin = try origin(session), storage = ProjectEditMemoryStorage(), journal = ApprovedTopicReviewJournal(storage: storage)
        let source = try ApprovedTopicReviewSynthetic(session: session, scenario: .unknownOnce, selectedCoverEnabled: true, selectedCoverReleaseBound: true, currentSession: { session })
        let flow = ApprovedTopicReviewFlow(origin: origin, session: session, source: source, journal: journal, stillCurrent: { true })
        await flow.load(); guard case .ready(let captured) = flow.state else { return XCTFail("Expected capture") }
        let confirmation = try XCTUnwrap(flow.review(captured)), claim = try XCTUnwrap(flow.claim(confirmation))
        XCTAssertEqual(try journal.read(session: session, topicID: 7901).current?.capture, captured)
        await flow.submit(claim); XCTAssertEqual(flow.state, .unconfirmed); XCTAssertEqual(source.submitCount, 1); flow.close()
        let restored = ApprovedTopicReviewFlow(origin: origin, session: session, source: source, journal: journal, stillCurrent: { true })
        await restored.load(); XCTAssertEqual(restored.snapshot?.current?.capture.selectedCover, captured.selectedCover)
        await restored.check(try XCTUnwrap(restored.snapshot))
        guard case .known = restored.state else { return XCTFail("Expected exact recovered receipt") }
        XCTAssertEqual(source.submitCount, 1); XCTAssertEqual(source.statusCount, 1); XCTAssertEqual(source.taskCount, 1)
        XCTAssertEqual(Set(source.requestIDs).count, 1); XCTAssertFalse(restored.canRetryExact)
    }
    func testCloseAfterClaimDoesNotSendOrDiscardFrozenCoverIntent() async throws {
        let session = try session(), origin = try origin(session), storage = ProjectEditMemoryStorage(), journal = ApprovedTopicReviewJournal(storage: storage)
        let source = try ApprovedTopicReviewSynthetic(session: session, selectedCoverEnabled: true, selectedCoverReleaseBound: true, currentSession: { session })
        let flow = ApprovedTopicReviewFlow(origin: origin, session: session, source: source, journal: journal, stillCurrent: { true })
        await flow.load(); guard case .ready(let value) = flow.state else { return XCTFail() }
        let confirmation = try XCTUnwrap(flow.review(value)), claim = try XCTUnwrap(flow.claim(confirmation))
        let saved = storage.data; flow.close(); await flow.submit(claim); flow.cancel(confirmation)
        XCTAssertEqual(source.submitCount, 0); XCTAssertEqual(storage.data, saved); XCTAssertEqual(flow.state, .closed)
        XCTAssertEqual(try journal.read(session: session, topicID: 7901).current?.capture.selectedCover, value.selectedCover)
    }
    func testApprovedPreparationPersistsCoverThroughPublicationUnknownAndStatusRecovery() async throws {
        let session = try session(), prepared = try preparation(), storage = ProjectEditMemoryStorage(), journal = ApprovedTopicReleasePublicationJournal(storage: storage)
        let source = try ApprovedTopicReleasePublicationSynthetic(session: session, scenario: .unknownOnce, currentSession: { session })
        let flow = ApprovedTopicReleasePublishFlow(session: session, topicID: 7901, source: source, journal: journal, stillCurrent: { true })
        flow.reload(); let confirmation = try XCTUnwrap(flow.review(prepared)), claim = try XCTUnwrap(flow.claim(confirmation))
        await flow.submit(claim); XCTAssertEqual(flow.state, .unconfirmed); flow.close()
        let restored = ApprovedTopicReleasePublishFlow(session: session, topicID: 7901, source: source, journal: journal, stillCurrent: { true })
        restored.reload(); XCTAssertEqual(restored.snapshot?.current?.prepared.selectedCover, prepared.selectedCover)
        await restored.checkStatus(try XCTUnwrap(restored.snapshot)); guard case .known = restored.state else { return XCTFail() }
        XCTAssertEqual(source.publishCount, 1); XCTAssertEqual(source.statusCount, 1); XCTAssertEqual(source.allocatedCount, 1)
        XCTAssertEqual(Set(source.requestIDs).count, 1)
    }
    func testApprovedDecoderStillRejectsAuthorOnlyAndArbitraryNodeMedia() throws {
        XCTAssertThrowsError(try preparation { $0["selectedCover"] = ApprovedTopicReviewSynthetic.selectedCoverFields(owner: 7) })
        XCTAssertThrowsError(try preparation { root in
            var chapters = root["chapters"]!.array!, chapter = chapters[0].object!, blocks = chapter["blocks"]!.array!
            var block = blocks[1].object!, node = block["node"]!.object!; node["imgUrl"] = .string("https://untrusted.invalid/image.png")
            block["node"] = .object(node); blocks[1] = .object(block); chapter["blocks"] = .array(blocks); chapters[0] = .object(chapter); root["chapters"] = .array(chapters)
        })
    }
    func testWrongOwnerPublicationPersistenceFailsBeforeWrite() throws {
        let prepared = try preparation { $0["selectedCover"] = ApprovedTopicReviewSynthetic.selectedCoverFields(owner: 8, releaseBound: true) }
        let session = try session(), storage = ProjectEditMemoryStorage(), journal = ApprovedTopicReleasePublicationJournal(storage: storage)
        XCTAssertThrowsError(try journal.begin(prepared, expected: journal.read(session: session, topicID: 7901), session: session))
        XCTAssertTrue(storage.data.isEmpty)
    }
    func testFrozenCoverEqualityRetainsExactLegacyUnicodeBytes() throws {
        func value(_ legacy: String) throws -> ApprovedTopicSelectedCover {
            var fields = ApprovedTopicReviewSynthetic.selectedCoverFields(owner: 7, releaseBound: true).object!
            fields["legacyTopicImageReference"] = .string(legacy)
            return try .decode(.object(fields), topicID: 7901, sourceConfigVersion: 1, legacyReference: legacy)
        }
        XCTAssertNotEqual(try value("é"), try value("e\u{301}"))
    }
}
