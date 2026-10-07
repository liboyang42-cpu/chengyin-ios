import XCTest
@testable import QuestifyCore

@MainActor final class WorkshopCreatorPendingControllerTests: XCTestCase {
    typealias DataFixture = WorkshopCreatorPendingCoreTests
    @MainActor final class Memory: TemplateAuthoringStorage {
        var values: [String: Data] = [:], fail = false, corrupt = false
        func read(_ key: String) throws -> Data? { values[key] }
        func write(_ data: Data, key: String) throws { if fail { throw WorkshopCreatorConsentIssue.storage }; values[key] = corrupt ? Data("{}".utf8) : data }
        func remove(_ key: String) throws { values.removeValue(forKey: key) }
    }
    @MainActor final class Source: WorkshopCreatorConsentServing {
        var reject = false, reads = 0, statusReads = 0
        var recovered: WorkshopCreatorDeclarationReceipt?
        func preview(sourceTemplateId: Int64, lifetime: WorkshopCreatorConsentLifetime) async throws -> WorkshopCreatorPreview {
            try lifetime.check(); reads += 1; guard !reject else { throw WorkshopCreatorConsentIssue.unavailable }; return try DataFixture.preview()
        }
        func status(command: WorkshopCreatorDeclarationCommand, lifetime: WorkshopCreatorConsentLifetime) async throws -> WorkshopCreatorDeclarationStatus { try lifetime.check(); statusReads += 1; if let recovered { return .recorded(recovered) }; return .notFound(command.requestId) }
        func declare(_ confirmation: WorkshopCreatorConsentConfirmation) async throws -> WorkshopCreatorDeclarationReceipt { throw WorkshopCreatorConsentIssue.disabled }
    }
    @MainActor final class Pending: WorkshopCreatorPendingServing {
        var commands: [WorkshopCreatorPendingCommand] = [], loseResponse = false, rejectReads = false, detailReads = 0, listReads = 0
        func author(_ confirmation: WorkshopCreatorPendingConfirmation) async throws -> WorkshopCreatorPendingMetadata {
            try confirmation.consume(); commands.append(confirmation.command)
            if loseResponse { throw WorkshopCreatorConsentIssue.unknown }
            return try WorkshopCreatorPendingWire.decode(WorkshopCreatorPendingMetadata.self, data: DataFixture.data(DataFixture.metadataJSON()))
        }
        func list(sourceTemplateId: Int64, afterTargetId: String?, lifetime: WorkshopCreatorConsentLifetime) async throws -> WorkshopCreatorPendingPage {
            try lifetime.check(); listReads += 1; guard !rejectReads else { throw WorkshopCreatorConsentIssue.unavailable }
            return try WorkshopCreatorPendingWire.decode(WorkshopCreatorPendingPage.self, data: DataFixture.data([
                "schema": "w18-creator-pending-package-list-v1", "sourceTemplateId": 91,
                "items": [try DataFixture.metadataJSON()], "hasMore": false, "nextCursor": NSNull()]))
        }
        func detail(sourceTemplateId: Int64, targetId: String, expectedRevision: String, lifetime: WorkshopCreatorConsentLifetime) async throws -> WorkshopCreatorPendingDetail {
            try lifetime.check(); detailReads += 1; guard !rejectReads else { throw WorkshopCreatorConsentIssue.unavailable }; return try DataFixture.detail()
        }
    }
    @MainActor final class Harness {
        let memory = Memory(), source = Source(), pending = Pending(), context: RuntimeDependencyContext
        var current: RuntimeDependencyContext?, writing = true, proposalReads = true, time = DataFixture.now
        lazy var lease = ContentDraftSessionLease(context: context, current: { [weak self] in self?.current })
        lazy var store = try! WorkshopCreatorPendingStore(storage: memory, context: context, sourceTemplateId: 91)
        lazy var declarationStore = try! WorkshopCreatorConsentPendingStore(storage: memory, context: context, sourceTemplateId: 91)
        lazy var controller = WorkshopCreatorPendingController(sourceTemplateId: 91, service: pending, previewService: source, lease: lease, store: store, declarationStore: declarationStore, canReadProposals: { [weak self] in self?.proposalReads == true },
            canAuthor: { [weak self] in self?.writing == true }, now: { [weak self] in self?.time ?? .distantFuture }, makeConsent: { [weak self] target, matches in
                guard let self else { return nil }
                let childLease = ContentDraftSessionLease(context: self.context, current: { [weak self] in self?.current })
                let childStore = try! WorkshopCreatorConsentPendingStore(storage: self.memory, context: self.context, sourceTemplateId: 91)
                return WorkshopCreatorConsentController(sourceTemplateId: 91, service: self.source, lease: childLease, store: childStore,
                    targets: { [target] }, canWrite: { true }, now: { [weak self] in self?.time ?? .distantFuture }, reviewMatchesPreview: matches)
            })
        init() throws {
            context = .init(market: .china, baseURL: URL(string: "https://example.com/native")!, role: "player", session: try .init(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic-secret", role: "player")); current = context
        }
        func fill() { controller.form.termsDocument = DataFixture.document; controller.form.commercialUse = "ALLOWED"; controller.form.adaptation = "LOCAL_ADAPTATION"; controller.form.translation = "PROHIBITED"; controller.form.allowedRegions = "CN,US"; controller.form.buyerKinds = "INDIVIDUAL,MERCHANT"; controller.form.themeLimit = "3"; controller.form.merchantLimit = "0"; controller.form.runLimit = "-1"; controller.form.priceMinor = "1499"; controller.form.currency = "CNY"; controller.form.expiresAt = "2026-10-08T12:00:00.123456Z" }
        func load(_ a: WorkshopCreatorPendingAppearance) async throws { await (try XCTUnwrap(controller.appear(a)))() }
    }
    func testBlankFormNeverInventsTermsPriceOrChoices() async throws {
        let h = try Harness(), a = WorkshopCreatorPendingAppearance(); try await h.load(a)
        XCTAssertEqual(h.controller.form, WorkshopCreatorPendingForm()); XCTAssertNil(h.controller.offerAuthor(a)); XCTAssertTrue(h.pending.commands.isEmpty); XCTAssertNil(try h.store.load())
    }
    func testCompleteTwentyOneFieldsPersistBeforeOfferedActionDispatchesOnce() async throws {
        let h = try Harness(), a = WorkshopCreatorPendingAppearance(); try await h.load(a); h.fill()
        let action = try XCTUnwrap(h.controller.offerAuthor(a)), saved = try XCTUnwrap(h.store.load())
        XCTAssertEqual(saved.termsDocument, DataFixture.document); XCTAssertEqual((try JSONSerialization.jsonObject(with: saved.data()) as? [String: Any])?.count, 21)
        XCTAssertTrue(h.pending.commands.isEmpty); await action(); await action(); XCTAssertEqual(h.pending.commands.count, 1); XCTAssertEqual(h.pending.commands[0], saved)
        XCTAssertNotNil(h.controller.receipt); XCTAssertNil(h.controller.declaration)
    }
    func testUnknownResultRetriesIdenticalCommandDespiteChangedFormAndReopen() async throws {
        let h = try Harness(), a = WorkshopCreatorPendingAppearance(); try await h.load(a); h.fill(); h.pending.loseResponse = true
        await (try XCTUnwrap(h.controller.offerAuthor(a)))(); let saved = try XCTUnwrap(h.store.load()); h.controller.form.termsDocument = "Different unsubmitted text"
        h.controller.close(a); let fresh = WorkshopCreatorPendingAppearance(); try await h.load(fresh)
        XCTAssertEqual(h.controller.pending, saved); h.pending.loseResponse = false
        let retry = try XCTUnwrap(h.controller.offerRetry(fresh)); XCTAssertEqual(h.pending.commands.count, 1); await retry()
        XCTAssertEqual(h.pending.commands.count, 2); XCTAssertEqual(h.pending.commands[0], h.pending.commands[1]); XCTAssertNotNil(h.controller.receipt)
    }
    func testQueuedAuthorAfterBackCannotDispatchAndCannotLoseSavedUuid() async throws {
        let h = try Harness(), old = WorkshopCreatorPendingAppearance(); try await h.load(old); h.fill()
        let action = try XCTUnwrap(h.controller.offerAuthor(old)), saved = try h.store.load(); h.controller.close(old)
        let fresh = WorkshopCreatorPendingAppearance(); try await h.load(fresh); await action()
        XCTAssertTrue(h.pending.commands.isEmpty); XCTAssertEqual(try h.store.load(), saved); XCTAssertNil(h.controller.appear(old)); XCTAssertEqual(h.controller.phase, .editing)
    }
    func testWriteRevocationAndOwnerChangeBeforeDispatchFailClosed() async throws {
        for ownerChange in [false, true] {
            let h = try Harness(), a = WorkshopCreatorPendingAppearance(); try await h.load(a); h.fill(); let action = try XCTUnwrap(h.controller.offerAuthor(a))
            if ownerChange { h.current = nil } else { h.writing = false }; await action(); XCTAssertTrue(h.pending.commands.isEmpty); XCTAssertNotNil(try h.store.load())
        }
    }
    func testFailedOrCorruptDurableWritePreventsDispatch() async throws {
        for corrupt in [false, true] {
            let h = try Harness(), a = WorkshopCreatorPendingAppearance(); try await h.load(a); h.fill(); h.memory.fail = !corrupt; h.memory.corrupt = corrupt
            XCTAssertNil(h.controller.offerAuthor(a)); XCTAssertTrue(h.pending.commands.isEmpty); XCTAssertEqual(h.controller.issue, .storage)
        }
    }
    func testHistoricAuthorReceiptCannotBypassCurrentSourceFailure() async throws {
        let h = try Harness(), a = WorkshopCreatorPendingAppearance(); try await h.load(a); h.fill(); let action = try XCTUnwrap(h.controller.offerAuthor(a)); h.source.reject = true; await action()
        XCTAssertNotNil(h.controller.receipt); XCTAssertNil(h.controller.preview); XCTAssertTrue(h.controller.items.isEmpty); XCTAssertNil(h.controller.declaration); XCTAssertFalse(h.controller.canRetry)
    }
    func testSelectedRealDetailRequiresFreshPreviewAndThreeUncheckedConsents() async throws {
        let h = try Harness(), a = WorkshopCreatorPendingAppearance(); try await h.load(a)
        await (try XCTUnwrap(h.controller.offerReview(try XCTUnwrap(h.controller.items.first), a)))()
        let consent = try XCTUnwrap(h.controller.declaration), displayed = WorkshopCreatorConsentAppearance(); await (try XCTUnwrap(consent.appear(displayed)))()
        consent.select(try XCTUnwrap(consent.targets.first), appearance: displayed)
        XCTAssertEqual(h.pending.detailReads, 1); XCTAssertTrue(consent.acknowledgments.isEmpty); XCTAssertFalse(consent.canConfirm); XCTAssertNil(consent.offerConfirm(displayed))
        for i in 0..<3 { consent.acknowledge(i, value: true, appearance: displayed) }; XCTAssertTrue(consent.canConfirm)
        await (try XCTUnwrap(h.controller.offerBackToProposals(a)))(); XCTAssertEqual(consent.phase, .invalidated); XCTAssertNil(h.controller.declaration)
    }
    func testExpiryAtSelectionCannotCreateDeclaration() async throws {
        let h = try Harness(), a = WorkshopCreatorPendingAppearance(); try await h.load(a); h.time = .distantFuture
        await (try XCTUnwrap(h.controller.offerReview(try XCTUnwrap(h.controller.items.first), a)))()
        XCTAssertNil(h.controller.declaration); XCTAssertNil(h.controller.selectedDetail); XCTAssertEqual(h.controller.phase, .failed)
    }
    func testRevokedSourceAfterListCannotCreateDeclaration() async throws {
        let h = try Harness(), a = WorkshopCreatorPendingAppearance(); try await h.load(a); h.source.reject = true
        await (try XCTUnwrap(h.controller.offerReview(try XCTUnwrap(h.controller.items.first), a)))()
        XCTAssertNil(h.controller.declaration); XCTAssertEqual(h.pending.detailReads, 0)
    }
    func testNewProposalRequiresReceiptThenClearsFormAndReloadsCurrentSource() async throws {
        let h = try Harness(), a = WorkshopCreatorPendingAppearance(); try await h.load(a); h.fill(); XCTAssertNil(h.controller.offerAnotherProposal(a))
        await (try XCTUnwrap(h.controller.offerAuthor(a)))(); let old = try XCTUnwrap(h.store.load()).requestId
        await (try XCTUnwrap(h.controller.offerAnotherProposal(a)))(); XCTAssertNil(try h.store.load()); XCTAssertEqual(h.controller.form, .init()); XCTAssertNil(h.controller.receipt)
        h.fill(); _ = try XCTUnwrap(h.controller.offerAuthor(a)); XCTAssertNotEqual(try XCTUnwrap(h.store.load()).requestId, old)
    }
    func testStorageIsOwnerRealmSourceBoundAndContainsNoToken() throws {
        let h = try Harness(), command = try DataFixture.command(); try h.store.retain(command)
        XCTAssertTrue(h.memory.values.values.allSatisfy { !String(decoding: $0, as: UTF8.self).contains("synthetic-secret") })
        let other = RuntimeDependencyContext(market: .china, baseURL: h.context.baseURL, role: "player", session: try .init(accountID: 8, epoch: 2, namespace: "synthetic", token: "other", role: "player"))
        XCTAssertNil(try WorkshopCreatorPendingStore(storage: h.memory, context: other, sourceTemplateId: 91).load())
        XCTAssertNil(try WorkshopCreatorPendingStore(storage: h.memory, context: h.context, sourceTemplateId: 92).load())
        XCTAssertThrowsError(try h.store.retain(DataFixture.command(document: "changed")))
    }
    func testHistoricalDeclarationRecoversBeforeRejectedCurrentSource() async throws {
        let h = try Harness(), target = try DataFixture.detail().declarationTarget(preview: DataFixture.preview(), now: DataFixture.now)
        let command = try WorkshopCreatorDeclarationCommand(preview: DataFixture.preview(), target: target); try h.declarationStore.retain(command)
        h.source.recovered = try WorkshopCreatorWire.decode(WorkshopCreatorDeclarationReceipt.self, data: DataFixture.data(WorkshopCreatorConsentTests.receipt(command)))
        h.source.reject = true; let a = WorkshopCreatorPendingAppearance(); try await h.load(a)
        XCTAssertNotNil(h.controller.declarationReceipt); XCTAssertEqual(h.source.statusReads, 1); XCTAssertNil(h.controller.preview); XCTAssertTrue(h.controller.items.isEmpty); XCTAssertNil(h.controller.declaration)
        XCTAssertEqual(h.pending.listReads, 0); XCTAssertTrue(h.pending.commands.isEmpty)
        h.controller.close(a); let fresh = WorkshopCreatorPendingAppearance(); try await h.load(fresh)
        XCTAssertNotNil(h.controller.declarationReceipt); XCTAssertEqual(h.source.statusReads, 2); XCTAssertNotNil(try h.declarationStore.load())
    }
    func testExpiredDeclarationHistoryNeedsNoProposalReadOrWriteAuthority() async throws {
        let h = try Harness(), target = try DataFixture.detail().declarationTarget(preview: DataFixture.preview(), now: DataFixture.now)
        let command = try WorkshopCreatorDeclarationCommand(preview: DataFixture.preview(), target: target); try h.declarationStore.retain(command)
        h.source.recovered = try WorkshopCreatorWire.decode(WorkshopCreatorDeclarationReceipt.self, data: DataFixture.data(WorkshopCreatorConsentTests.receipt(command)))
        h.proposalReads = false; h.writing = false; h.time = .distantFuture; h.source.reject = true
        try await h.load(.init()); XCTAssertNotNil(h.controller.declarationReceipt); XCTAssertEqual(h.source.statusReads, 1); XCTAssertEqual(h.source.reads, 0)
        XCTAssertEqual(h.pending.listReads, 0); XCTAssertEqual(h.pending.detailReads, 0); XCTAssertFalse(h.controller.canSubmit); XCTAssertFalse(h.controller.canRetry); XCTAssertNil(h.controller.declaration)
    }

}
