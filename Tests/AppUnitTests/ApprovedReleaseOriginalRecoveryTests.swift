import XCTest
@testable import Questify

@MainActor final class ApprovedReleaseOriginalRecoveryTests: XCTestCase {
    private final class Owner {
        var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "original-recovery")
    }
    private final class Source: ApprovedTopicReleasePublishing {
        let original: ProjectEditSession
        let owner: Owner
        var statusAllowed = true
        var publishAllowed = false
        var requests: [ApprovedTopicReleasePublicationJournal.Record] = []
        var publishCalls = 0
        var failure: Error? = ApprovedTopicReleaseError.unavailable
        var hold = false
        var started: XCTestExpectation?
        var continuation: CheckedContinuation<ApprovedTopicReleasePublicationReceipt, Error>?
        init(_ owner: Owner) throws { self.owner = owner; original = try XCTUnwrap(owner.session) }
        func isCurrent(session: ProjectEditSession) -> Bool { session == original && owner.session == original }
        func canPublish(session: ProjectEditSession) -> Bool { isCurrent(session: session) && publishAllowed }
        func canCheckStatus(session: ProjectEditSession) -> Bool { isCurrent(session: session) && statusAllowed }
        func publish(_ record: ApprovedTopicReleasePublicationJournal.Record, session: ProjectEditSession) async throws -> ApprovedTopicReleasePublicationReceipt {
            publishCalls += 1; throw ApprovedTopicReleaseError.notConfigured
        }
        func status(_ record: ApprovedTopicReleasePublicationJournal.Record, session: ProjectEditSession) async throws -> ApprovedTopicReleasePublicationReceipt {
            requests.append(record)
            if hold { return try await withCheckedThrowingContinuation { continuation = $0; started?.fulfill() } }
            if let failure { throw failure }
            return try ApprovedReleaseOriginalRecoveryTests.receipt(record)
        }
    }
    private final class OriginalAcknowledgmentService: ProjectEditServing {
        var authority: ProjectEditServiceAuthority { .synthetic }
        func preflight(topicID: Int?, session: ProjectEditSession) async throws -> ProjectEditPreflight {
            .init(capability: .init(canProPublish: true, remaining: nil), snapshot: nil)
        }
        func submit(_ operation: ProjectEditPending, session: ProjectEditSession) async -> ProjectEditWriteOutcome {
            .acknowledged(operationID: operation.operationID, topicID: 7901)
        }
        func terminalReceipt(operationID: UUID, session: ProjectEditSession) async throws -> ProjectEditWriteOutcome? { nil }
    }
    private struct Context {
        let owner: Owner
        let storage: ProjectEditMemoryStorage
        let source: Source
        let journal: ApprovedTopicReleasePublicationJournal
        let model: ProjectEditModel
        let controller: ApprovedReleaseOriginalRecovery
    }
    private func setup(scope: ProjectEditScope = .full, acknowledged: Bool = false, topic: Int = 7901, ownerKind: ProjectEditOwner = .personal, stored: ProjectEditMemoryStorage? = nil) async throws -> Context {
        let owner = Owner(), storage = stored ?? ProjectEditMemoryStorage(), source = try Source(owner)
        let journal = ApprovedTopicReleasePublicationJournal(storage: storage)
        var draft = ProjectEditSyntheticFixtures.draft(); draft.owner = ownerKind
        let snapshot = ProjectEditSnapshot(topicID: acknowledged ? nil : topic, scope: scope, draft: draft)
        let co = ProjectEditCoordinator(initial: snapshot, service: ProjectEditSyntheticService(scenario: .bundlePending, snapshot: snapshot),
            store: ProjectEditLocalStore(storage: storage), releasePublicationSource: source, releasePublicationJournal: journal,
            currentSession: { owner.session })
        let model = ProjectEditModel(coordinator: co); await model.load()
        if acknowledged { model.review(); await model.submit(try XCTUnwrap(model.confirmation)) }
        return .init(owner: owner, storage: storage, source: source, journal: journal, model: model,
                     controller: ApprovedReleaseOriginalRecovery(model: model))
    }
    private func prepared(newer: Bool = false) throws -> ApprovedTopicReleasePreparation {
        let envelope = try JSONDecoder().decode([String: ProjectEditJSON].self, from: ApprovedTopicReleaseSyntheticSource.preparationData())
        var row = try XCTUnwrap(envelope["data"]?.object)
        if newer { row["auditTaskVersion"] = .number(3); row["headRevision"] = .number(1) }
        return try .decode(.object(row), topicID: 7901, auditTaskID: 3301)
    }
    private static func receipt(_ record: ApprovedTopicReleasePublicationJournal.Record) throws -> ApprovedTopicReleasePublicationReceipt {
        let c = record.command
        return try .decode(.object(["releaseId": .number(501), "topicId": .number(Decimal(c.topicID)),
            "sourceConfigVersion": .number(Decimal(record.prepared.sourceConfigVersion)), "auditTaskId": .number(Decimal(c.auditTaskID)),
            "auditRecordId": .number(81), "auditTaskVersion": .number(Decimal(c.auditTaskVersion)), "schemaVersion": .number(1),
            "manifestHash": .string(c.expectedManifestHash), "auditSnapshotHash": .string(c.auditSnapshotHash), "currentlyApproved": .bool(true)]),
            command: c, prepared: record.prepared)
    }
    // Only test setup creates original durable records. The recovery subject has no journal writer surface.
    @discardableResult private func seed(_ c: Context, known: Bool = false) throws -> ApprovedTopicReleasePublicationJournal.Snapshot {
        let s = try XCTUnwrap(c.owner.session)
        let original = try c.journal.begin(prepared(), expected: c.journal.read(session: s, topicID: 7901), session: s)
        if known { return try c.journal.record(Self.receipt(XCTUnwrap(original.current)), expected: original, session: s) }
        return original
    }
    private func open(_ c: Context) throws -> ApprovedReleaseOriginalRecovery.Presentation {
        c.controller.open(try XCTUnwrap(c.controller.capture()))
        return try XCTUnwrap(c.controller.presentation)
    }
    func testStatusOnlyWithoutPrepareOrAcknowledgmentUsesAcceptedServerTopic() async throws {
        let c = try await setup(); let original = try seed(c), before = c.storage.data
        XCTAssertNil(c.model.submissionEvidence); XCTAssertNil(c.model.coordinator.releasePreparationSource)
        XCTAssertFalse(c.source.canPublish(session: c.source.original))
        c.model.draft.preserved["id"] = .number(9999)
        let p = try open(c); p.reader.reload(); XCTAssertEqual(p.reader.snapshot, original)
        await p.reader.checkStatus(original)
        XCTAssertEqual(c.source.requests, [try XCTUnwrap(original.current)])
        XCTAssertEqual(c.source.publishCalls, 0); XCTAssertEqual(c.storage.data, before)
    }
    func testFrozenEditorCanReadOriginalStatusWithoutEditingOrPrepareAuthority() async throws {
        let c = try await setup(scope: .sellingFrozen); let original = try seed(c)
        XCTAssertFalse(c.model.canEdit)
        let p = try open(c); p.reader.reload(); await p.reader.checkStatus(original)
        XCTAssertEqual(c.source.requests.count, 1); XCTAssertEqual(c.source.publishCalls, 0)
    }
    func testStrictNewTopicAcknowledgmentSelectsCompletedTopicNotMutableDraft() async throws {
        let c = try await setup(acknowledged: true); try seed(c)
        XCTAssertNil(c.model.coordinator.snapshot?.topicID)
        c.model.draft.preserved["id"] = .number(8888)
        let p = try open(c); XCTAssertEqual(p.opening.topicID, 7901)
        p.reader.reload(); XCTAssertEqual(p.reader.snapshot?.topicID, 7901)
    }
    func testStrictOriginalAcknowledgmentNeedsNoNewBundleOrPrepareEvidence() async throws {
        let owner = Owner(), storage = ProjectEditMemoryStorage(), source = try Source(owner)
        let co = ProjectEditCoordinator(initial: .init(draft: ProjectEditSyntheticFixtures.draft()), service: OriginalAcknowledgmentService(),
            store: ProjectEditLocalStore(storage: storage), releasePublicationSource: source,
            releasePublicationJournal: .init(storage: storage), currentSession: { owner.session })
        let model = ProjectEditModel(coordinator: co); await model.load(); model.review()
        await model.submit(try XCTUnwrap(model.confirmation))
        XCTAssertNotNil(model.submissionEvidence); XCTAssertNil(model.submissionEvidence?.bundleAcknowledgment)
        XCTAssertTrue(co.pending?.hasConsistentAcknowledgment == true); XCTAssertEqual(co.pending?.completedTopicID, 7901)
        let controller = ApprovedReleaseOriginalRecovery(model: model)
        XCTAssertEqual(controller.capture()?.topicID, 7901); XCTAssertTrue(source.requests.isEmpty)
    }
    func testLocalDraftIDWithoutAcceptedSnapshotOrStrictAckCannotChooseTopic() async throws {
        let owner = Owner(), storage = ProjectEditMemoryStorage(), source = try Source(owner)
        var draft = ProjectEditSyntheticFixtures.draft(); draft.preserved["id"] = .number(7901)
        let co = ProjectEditCoordinator(initial: .init(draft: draft), service: ProjectEditSyntheticService(),
            store: ProjectEditLocalStore(storage: storage), releasePublicationSource: source,
            releasePublicationJournal: .init(storage: storage), currentSession: { owner.session })
        let model = ProjectEditModel(coordinator: co); await model.load()
        XCTAssertNil(ApprovedReleaseOriginalRecovery(model: model).capture()); XCTAssertTrue(source.requests.isEmpty)
    }
    func testUnconfiguredAndRevokedAreNeverEmptyJournal() async throws {
        let c = try await setup(); c.source.statusAllowed = false
        XCTAssertNil(c.controller.capture()); XCTAssertTrue(c.source.requests.isEmpty)
        c.source.statusAllowed = true; let p = try open(c)
        XCTAssertFalse(p.reader.loaded); p.reader.reload()
        XCTAssertEqual(p.reader.state, .idle); XCTAssertEqual(p.reader.snapshot?.records, [])
        c.source.publishAllowed = true; c.source.statusAllowed = false
        XCTAssertTrue(c.source.isCurrent(session: c.source.original)); XCTAssertFalse(p.reader.isCurrent)
        XCTAssertNil(p.reader.snapshot); XCTAssertFalse(p.reader.canCheckStatus)
    }
    func testMissingSourceOrJournalCannotOfferRecovery() async throws {
        let owner = Owner(), storage = ProjectEditMemoryStorage(), source = try Source(owner)
        for includeSource in [false, true] {
            let initial = ProjectEditSnapshot(topicID: 7901, draft: ProjectEditSyntheticFixtures.draft())
            let co = ProjectEditCoordinator(initial: initial, service: ProjectEditSyntheticService(snapshot: initial), store: ProjectEditLocalStore(storage: storage),
                releasePublicationSource: includeSource ? source : nil, currentSession: { owner.session })
            let model = ProjectEditModel(coordinator: co); await model.load()
            XCTAssertNil(ApprovedReleaseOriginalRecovery(model: model).capture())
        }
    }
    func testSessionOwnerEpochRealmViewerAndConfigurationChangesRejectCapturedOpening() async throws {
        let variants: [ProjectEditSession] = [
            try .init(accountID: 8, epoch: 1, storageNamespace: "original-recovery"),
            try .init(accountID: 7, epoch: 2, storageNamespace: "original-recovery"),
            try .init(accountID: 7, epoch: 1, storageNamespace: "other-realm"),
            try .init(accountID: 7, epoch: 1, storageNamespace: "original-recovery", viewerRevision: 1),
            try .init(accountID: 7, epoch: 1, storageNamespace: "original-recovery", configurationRevision: 1)]
        for session in variants {
            let c = try await setup(), opening = try XCTUnwrap(c.controller.capture())
            c.owner.session = session; c.controller.open(opening)
            XCTAssertNil(c.controller.presentation); XCTAssertFalse(c.controller.isCurrent(opening))
            XCTAssertTrue(c.source.requests.isEmpty)
        }
    }
    func testWrongTopicSourceJournalAndEditorVisitRejectOpening() async throws {
        let c = try await setup(), other = try await setup(topic: 7902)
        let opening = try XCTUnwrap(c.controller.capture())
        other.controller.open(opening); XCTAssertNil(other.controller.presentation)
        let wrongTopic = ApprovedReleaseOriginalRecovery.Opening(session: opening.session, incarnation: opening.incarnation,
            identity: opening.identity, snapshot: opening.snapshot, acknowledged: opening.acknowledged, topicID: 9999,
            source: c.source, journal: c.journal)
        c.controller.open(wrongTopic); XCTAssertNil(c.controller.presentation)
        let replacedSource = ApprovedReleaseOriginalRecovery.Opening(session: opening.session, incarnation: opening.incarnation,
            identity: opening.identity, snapshot: opening.snapshot, acknowledged: opening.acknowledged, topicID: opening.topicID,
            source: try Source(c.owner), journal: c.journal)
        c.controller.open(replacedSource); XCTAssertNil(c.controller.presentation)
        let replacedJournal = ApprovedReleaseOriginalRecovery.Opening(session: opening.session, incarnation: opening.incarnation,
            identity: opening.identity, snapshot: opening.snapshot, acknowledged: opening.acknowledged, topicID: opening.topicID,
            source: c.source, journal: .init(storage: c.storage))
        c.controller.open(replacedJournal); XCTAssertNil(c.controller.presentation)
        c.model.coordinator.beginEditorVisit(UUID()); c.controller.open(opening); XCTAssertNil(c.controller.presentation)
    }
    func testMerchantOwnerIsRejected() async throws {
        let c = try await setup(ownerKind: .merchant); XCTAssertNil(c.controller.capture())
    }
    func testUnknownNotFoundAndOrdinaryFailurePreserveExactRecordWithoutReplay() async throws {
        let c = try await setup(), original = try seed(c), before = c.storage.data, p = try open(c)
        p.reader.reload()
        for error in [APIError.httpStatus(404), APIError.httpStatus(503)] {
            c.source.failure = error; await p.reader.checkStatus(original)
            XCTAssertEqual(p.reader.state, .unconfirmed); XCTAssertEqual(p.reader.snapshot, original)
            XCTAssertEqual(c.storage.data, before)
        }
        XCTAssertEqual(c.source.requests.map(\.command), [original.current!.command, original.current!.command])
        XCTAssertEqual(c.source.publishCalls, 0)
    }
    func testKnownReceiptAndCapturedSummarySurviveFailedLatestRead() async throws {
        let c = try await setup(), original = try seed(c, known: true), before = c.storage.data, p = try open(c)
        p.reader.reload(); await p.reader.checkStatus(original)
        XCTAssertTrue(p.reader.lastStatusCheckFailed); XCTAssertEqual(p.reader.snapshot, original)
        XCTAssertEqual(p.reader.state, .known(try XCTUnwrap(original.current?.receipt)))
        p.reader.inspect(try XCTUnwrap(original.current))
        XCTAssertEqual(p.reader.inspectedResult?.record.prepared, original.current?.prepared)
        XCTAssertEqual(c.storage.data, before); XCTAssertEqual(c.source.publishCalls, 0)
    }
    func testSuccessfulReadPersistsMatchingReceiptWithoutNewRequest() async throws {
        let c = try await setup(), original = try seed(c), p = try open(c)
        c.source.failure = nil; p.reader.reload(); await p.reader.checkStatus(original)
        XCTAssertEqual(p.reader.snapshot?.current?.command, original.current?.command)
        XCTAssertEqual(p.reader.snapshot?.current?.prepared, original.current?.prepared)
        XCTAssertEqual(p.reader.snapshot?.current?.receipt?.releaseID, 501)
        XCTAssertEqual(c.source.requests.count, 1); XCTAssertEqual(c.source.publishCalls, 0)
    }
    func testHistoryInspectsCapturedRecordsButStatusUsesOnlyLatestOriginalSnapshot() async throws {
        let c = try await setup(), first = try seed(c, known: true), s = try XCTUnwrap(c.owner.session)
        let latest = try c.journal.begin(prepared(newer: true), expected: first, session: s), before = c.storage.data
        let p = try open(c); p.reader.reload(); p.reader.inspect(try XCTUnwrap(first.current))
        let inspection = try XCTUnwrap(p.reader.inspectedResult)
        XCTAssertEqual(inspection.record, first.current); XCTAssertFalse(p.reader.canCheckStatus)
        p.reader.dismiss(inspection); await p.reader.checkStatus(first); XCTAssertTrue(c.source.requests.isEmpty)
        await p.reader.checkStatus(latest)
        XCTAssertEqual(c.source.requests, [try XCTUnwrap(latest.current)]); XCTAssertEqual(c.storage.data, before)
    }
    func testUnreadableAndDamagedStorageNeverAppearEmptyOrEraseBytes() async throws {
        let c = try await setup(); try seed(c)
        let p = try open(c), before = c.storage.data
        c.storage.failReads = true; p.reader.reload(); XCTAssertEqual(p.reader.state, .unavailable)
        XCTAssertFalse(p.reader.canCheckStatus); XCTAssertEqual(p.reader.storageIssue, .unreadable); XCTAssertEqual(c.storage.data, before)
        c.storage.failReads = false
        let key = try XCTUnwrap(c.storage.data.keys.first { $0.hasPrefix("approved-topic-release.v1.") })
        c.storage.data[key] = Data("damaged".utf8); let damaged = c.storage.data
        p.reader.reload(); XCTAssertEqual(p.reader.state, .unavailable); XCTAssertEqual(p.reader.storageIssue, .damaged); XCTAssertEqual(c.storage.data, damaged)
        XCTAssertTrue(c.source.requests.isEmpty)
    }
    func testWrongOwnerOrTopicEnvelopeIsDamagedStorageWithoutClearingOriginal() async throws {
        for field in ["ownerKey", "topicId"] {
            let c = try await setup(); try seed(c)
            let key = try XCTUnwrap(c.storage.data.keys.first { $0.hasPrefix("approved-topic-release.v1.") })
            var row = try JSONDecoder().decode([String: ProjectEditJSON].self, from: XCTUnwrap(c.storage.data[key]))
            row[field] = field == "ownerKey" ? .string("another-owner") : .number(9999)
            c.storage.data[key] = try JSONEncoder().encode(row); let before = c.storage.data, p = try open(c)
            p.reader.reload(); XCTAssertEqual(p.reader.state, .unavailable); XCTAssertEqual(p.reader.storageIssue, .damaged)
            XCTAssertEqual(c.storage.data, before); XCTAssertTrue(c.source.requests.isEmpty)
        }
    }
    func testCloseReopenOldBindingsAndResultCoverCannotDestroySuccessor() async throws {
        let c = try await setup(); let original = try seed(c), before = c.storage.data, first = try open(c)
        first.reader.reload(); first.reader.inspect(try XCTUnwrap(original.current))
        let result = try XCTUnwrap(first.reader.inspectedResult), resultBinding = first.reader.resultBinding(result)
        XCTAssertTrue(c.controller.isPresented(first), "Child inspection must not close its carrier")
        first.reader.dismiss(result); first.reader.inspect(try XCTUnwrap(original.current))
        let successorResult = try XCTUnwrap(first.reader.inspectedResult)
        resultBinding.wrappedValue = nil; XCTAssertTrue(first.reader.isInspecting(successorResult))
        let binding = c.controller.binding(first); c.controller.close(first)
        let second = try open(c); binding.wrappedValue = nil; c.controller.close(first)
        XCTAssertTrue(c.controller.isPresented(second)); XCTAssertEqual(first.reader.state, .closed)
        second.reader.reload(); XCTAssertEqual(second.reader.snapshot, original); XCTAssertEqual(c.storage.data, before)
    }
    func testBackgroundAndLeavePreserveJournalAndInvalidateOldReader() async throws {
        let c = try await setup(), original = try seed(c), before = c.storage.data, first = try open(c)
        first.reader.reload(); c.controller.setActive(false)
        XCTAssertNil(c.controller.presentation); XCTAssertNil(c.controller.capture()); await first.reader.checkStatus(original)
        c.controller.setActive(true); let second = try open(c); second.reader.reload()
        XCTAssertEqual(second.reader.snapshot, original); c.model.leave()
        XCTAssertFalse(c.controller.isPresented(second)); await second.reader.checkStatus(original)
        XCTAssertEqual(c.storage.data, before); XCTAssertTrue(c.source.requests.isEmpty)
    }
    func testRestartReopensOriginalDurableIntentWithoutReplayOrMigration() async throws {
        let c = try await setup(), original = try seed(c), first = try open(c), before = c.storage.data
        first.reader.reload(); c.controller.close(first); c.model.leave()
        let restarted = try await setup(stored: c.storage), p = try open(restarted)
        p.reader.reload(); XCTAssertEqual(p.reader.snapshot, original)
        XCTAssertEqual(c.storage.data, before); XCTAssertEqual(restarted.source.publishCalls, 0)
        XCTAssertTrue(restarted.source.requests.isEmpty)
    }
    func testLateOldCallbackCannotPersistOrCloseNewPresentation() async throws {
        let c = try await setup(), original = try seed(c), first = try open(c), before = c.storage.data
        first.reader.reload(); c.source.hold = true; c.source.started = expectation(description: "status started")
        let task = Task { await first.reader.checkStatus(original) }
        await fulfillment(of: [try XCTUnwrap(c.source.started)], timeout: 1)
        c.controller.close(first); let second = try open(c); second.reader.reload()
        c.source.continuation?.resume(returning: try Self.receipt(XCTUnwrap(original.current)))
        c.source.continuation = nil; await task.value
        XCTAssertTrue(c.controller.isPresented(second)); XCTAssertEqual(c.storage.data, before)
        XCTAssertEqual(second.reader.state, .unconfirmed); XCTAssertEqual(c.source.publishCalls, 0)
    }
    func testRevocationWhileStatusIsSuspendedCannotSaveLateReceipt() async throws {
        let c = try await setup(), original = try seed(c), p = try open(c), before = c.storage.data
        p.reader.reload(); c.source.publishAllowed = true; c.source.hold = true
        c.source.started = expectation(description: "status before revocation")
        let task = Task { await p.reader.checkStatus(original) }
        await fulfillment(of: [try XCTUnwrap(c.source.started)], timeout: 1)
        c.source.statusAllowed = false
        c.source.continuation?.resume(returning: try Self.receipt(XCTUnwrap(original.current)))
        c.source.continuation = nil; await task.value
        XCTAssertFalse(p.reader.isCurrent); XCTAssertNil(p.reader.snapshot); XCTAssertEqual(c.storage.data, before)
        XCTAssertEqual(c.source.publishCalls, 0)
    }
    func testRecoveryCatalogUsesAppEnglishAndSimplifiedChineseLocales() {
        for key in ApprovedReleaseOriginalRecoveryText.allCases {
            let en = key.value(locale: Locale(identifier: "en")), zh = key.value(locale: Locale(identifier: "zh-Hans"))
            XCTAssertFalse(en.isEmpty); XCTAssertFalse(zh.isEmpty); XCTAssertNotEqual(en, "recovery." + key.rawValue)
            XCTAssertNotEqual(zh, "recovery." + key.rawValue); XCTAssertNotEqual(en, zh)
        }
    }
}
