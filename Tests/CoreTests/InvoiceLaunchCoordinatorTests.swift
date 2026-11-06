import XCTest
@testable import QuestifyCore

@MainActor final class InvoiceLaunchCoordinatorTests: XCTestCase {
    private typealias S = InvoiceLaunchTestSupport
    func testApplyWritesDurablyBeforeDispatchAndReadsOriginalID() async throws {
        let h = try S.Harness(); h.wire.responses = [try S.success(S.application()), try S.success(S.application())]
        h.wire.beforeSend = { XCTAssertNotNil(try h.store.load()) }
        let result = try await h.coordinator().apply(h.command())
        XCTAssertEqual(result.id, 51); XCTAssertNil(try h.store.load())
        XCTAssertEqual(h.wire.requests.map { $0.url!.lastPathComponent }, ["apply", "detail"])
        let body = try JSONSerialization.jsonObject(with: h.wire.requests[0].httpBody!) as! [String: Any]
        XCTAssertEqual(Set(body.keys), ["requestId", "titleId", "orderIds"])
        XCTAssertEqual(body["requestId"] as? String, "synthetic-original-request")
    }
    func testStorageFailureOrDisabledMutationPreventsDispatch() async throws {
        let h = try S.Harness(); h.memory.failWrite = true
        await S.expect(.storageUnavailable) { _ = try await h.coordinator().apply(h.command()) }
        XCTAssertTrue(h.wire.requests.isEmpty)
        h.memory.failWrite = false; h.mutations = false
        await S.expect(.disabled) { _ = try await h.coordinator().apply(h.command()) }
        XCTAssertTrue(h.wire.requests.isEmpty); XCTAssertNil(try h.store.load())
    }
    func testUnknownApplyRetainsOriginalAndNeverUsesListOrAnotherWrite() async throws {
        let h = try S.Harness(); h.wire.failNext = true
        await S.expect(.outcomeUnknown) { _ = try await h.coordinator().apply(h.command()) }
        let original = try XCTUnwrap(h.store.load())
        let restarted = try S.Harness(memory: h.memory, captured: S.session(epoch: 2))
        await S.expect(.originalReadUnavailable) { _ = try await restarted.coordinator().recover() }
        await S.expect(.pendingConflict) { _ = try await restarted.coordinator().apply(restarted.command()) }
        XCTAssertTrue(restarted.wire.requests.isEmpty); XCTAssertEqual(try restarted.store.load(), original)
    }
    func testReadFailureAfterApplyRecoversByCheckpointedOriginalIDOnly() async throws {
        let h = try S.Harness(); h.wire.responses = [try S.success(S.application())]
        do { _ = try await h.coordinator().apply(h.command()); XCTFail("Expected failed readback") } catch {}
        XCTAssertEqual(try h.store.load()?.applicationID, 51)
        let restarted = try S.Harness(memory: h.memory, captured: S.session(epoch: 2))
        restarted.wire.responses = [try S.success(S.application(status: "ISSUED"))]
        let result = try await restarted.coordinator().recover()
        if case .application(let app) = result { XCTAssertEqual(app.status, .issued) } else { XCTFail("Expected original application") }
        XCTAssertEqual(restarted.wire.requests.count, 1)
        XCTAssertEqual(restarted.wire.requests.first?.url?.lastPathComponent, "detail")
        XCTAssertNil(try restarted.store.load())
    }
    func testCodedRollbackClearsOnlyWriteFailureAndInProgressKeepsOriginal() async throws {
        let h = try S.Harness(); h.wire.responses = [try S.failure("INVOICE_ORDER_NOT_ELIGIBLE")]
        await S.expect(.rejected("INVOICE_ORDER_NOT_ELIGIBLE")) { _ = try await h.coordinator().apply(h.command()) }
        XCTAssertNil(try h.store.load())
        h.wire.responses = [try S.failure("INVOICE_REQUEST_IN_PROGRESS")]
        await S.expect(.outcomeUnknown) { _ = try await h.coordinator().apply(h.command()) }
        XCTAssertNotNil(try h.store.load())
        let read = try S.Harness(); read.wire.responses = [try S.success(S.application()), try S.failure("INVOICE_NOT_FOUND")]
        await S.expect(.outcomeUnknown) { _ = try await read.coordinator().apply(read.command()) }
        XCTAssertNotNil(try read.store.load())
    }
    func testSaveTitleReadsMaskProjectionAndUnknownNeverResubmitsPII() async throws {
        let h = try S.Harness(), draft = try InvoiceLaunchTitleDraft(titleType: "PERSONAL", titleName: "Synthetic title")
        h.wire.responses = [try S.success(S.title), try S.success([S.title])]
        let result = try await h.coordinator().saveTitle(draft); XCTAssertEqual(result.id, 11); XCTAssertNil(try h.store.load())
        h.wire.failNext = true
        await S.expect(.outcomeUnknown) { _ = try await h.coordinator().saveTitle(draft) }
        let count = h.wire.requests.count
        await S.expect(.originalReadUnavailable) { _ = try await h.coordinator().recover() }
        XCTAssertEqual(h.wire.requests.count, count)
        let saved = String(decoding: try XCTUnwrap(h.memory.values.values.first), as: UTF8.self)
        XCTAssertFalse(saved.contains("Synthetic title")); XCTAssertFalse(saved.contains("taxNo"))
    }
    func testUnknownCancelRecoversOnlyCancelledOriginalDetail() async throws {
        let h = try S.Harness(); h.wire.failNext = true
        await S.expect(.outcomeUnknown) { _ = try await h.coordinator().cancel(id: 51) }
        h.wire.responses = [try S.success(S.application())]
        await S.expect(.outcomeUnknown) { _ = try await h.coordinator().recover() }; XCTAssertNotNil(try h.store.load())
        h.wire.responses = [try S.success(S.application(status: "CANCELLED"))]
        _ = try await h.coordinator().recover(); XCTAssertNil(try h.store.load())
        XCTAssertEqual(h.wire.requests.map { $0.url!.lastPathComponent }, ["cancel", "detail", "detail"])
    }
    func testDeleteTitleUsesOriginalIDAndReadsAuthoritativeAbsence() async throws {
        let h = try S.Harness(); h.wire.responses = [try S.success(NSNull()), try S.success([])]
        try await h.coordinator().deleteTitle(id: 11); XCTAssertNil(try h.store.load())
        h.wire.failNext = true
        await S.expect(.outcomeUnknown) { try await h.coordinator().deleteTitle(id: 11) }
        h.wire.responses = [try S.success([])]
        let recovered = try await h.coordinator().recover(); XCTAssertEqual(recovered, .titleAbsent(11))
        XCTAssertEqual(h.wire.requests.map { $0.url!.lastPathComponent }, ["delete", "titles", "delete", "titles"])
    }
    func testStaleMutationResponsePreservesPendingAndDoesNotExpireNewAccount() async throws {
        let h = try S.Harness(); h.wire.responses = [try S.success(S.application())]
        h.wire.afterSend = { h.current = try? S.session(account: 8) }
        await S.expect(.outcomeUnknown) { _ = try await h.coordinator().apply(h.command()) }
        XCTAssertNotNil(try h.store.load()); XCTAssertNil(try h.store.load()?.applicationID)
        XCTAssertEqual(h.wire.requests.count, 1); XCTAssertEqual(h.unauthorized, 0)
    }
    func testConcurrentDoubleTapAndMismatchedReceiptCannotReleaseOriginal() async throws {
        let h = try S.Harness(), coordinator = try h.coordinator(); h.wire.suspendNext = true
        let first = Task { try await coordinator.apply(h.command()) }
        for _ in 0..<1000 { if h.wire.suspended != nil { break }; await Task.yield() }
        XCTAssertNotNil(h.wire.suspended)
        await S.expect(.pendingConflict) { _ = try await coordinator.apply(h.command()) }
        h.wire.suspended?.resume(returning: try S.success(S.application(orders: [99]))); h.wire.suspended = nil
        await S.expect(.outcomeUnknown) { _ = try await first.value }
        XCTAssertNotNil(try h.store.load()); XCTAssertEqual(h.wire.requests.count, 1)
    }
    func testRequestReusedAndServerErrorsNeverPermitAnotherApply() async throws {
        for response in [try S.failure("INVOICE_REQUEST_REUSED"), (Data("{}".utf8), 502),
                         (Data("{\"code\":200,\"data\":null}".utf8), 200)] {
            let h = try S.Harness(); h.wire.responses = [response]
            await S.expect(.outcomeUnknown) { _ = try await h.coordinator().apply(h.command()) }
            XCTAssertNotNil(try h.store.load())
            await S.expect(.pendingConflict) { _ = try await h.coordinator().apply(h.command()) }
            XCTAssertEqual(h.wire.requests.count, 1)
        }
    }
    func testMissingOriginalDetailAndPresentTitleRetainUnknownRecords() async throws {
        let h = try S.Harness(); h.wire.failNext = true
        await S.expect(.outcomeUnknown) { _ = try await h.coordinator().cancel(id: 51) }
        h.wire.responses = [try S.failure("INVOICE_NOT_FOUND")]
        await S.expect(.outcomeUnknown) { _ = try await h.coordinator().recover() }
        XCTAssertNotNil(try h.store.load())
        let deletion = try S.Harness(); deletion.wire.failNext = true
        await S.expect(.outcomeUnknown) { try await deletion.coordinator().deleteTitle(id: 11) }
        deletion.wire.responses = [try S.success([S.title])]
        await S.expect(.outcomeUnknown) { _ = try await deletion.coordinator().recover() }
        XCTAssertNotNil(try deletion.store.load())
    }
    func testCancelAcknowledgementRequiresSeparateOriginalReadAndRetainsOnStorageFailure() async throws {
        let h = try S.Harness(); h.wire.responses = [try S.success(S.application(status: "CANCELLED")), try S.success(S.application(status: "CANCELLED"))]
        h.memory.failRemove = true
        await S.expect(.storageUnavailable) { _ = try await h.coordinator().cancel(id: 51) }
        XCTAssertNotNil(try h.store.load())
        XCTAssertEqual(h.wire.requests.map { $0.url!.lastPathComponent }, ["cancel", "detail"])
    }
    func testOverviewReadsAllServerListsAndPreservesPendingIdentity() async throws {
        let h = try S.Harness(), pending = InvoiceLaunchPending(kind: .apply, apply: try h.command())
        try h.store.save(pending)
        let orders = S.application()["orders"]!
        h.wire.responses = [try S.success([S.title]), try S.success(orders), try S.success([S.application()])]
        let result = try await h.coordinator().overview()
        XCTAssertEqual(result.titles.first?.id, 11)
        XCTAssertEqual(result.eligibleOrders.map(\.orderId), [21, 22])
        XCTAssertEqual(result.applications.first?.totalAmount, Decimal(string: "14.25"))
        XCTAssertEqual(result.pending, pending); XCTAssertEqual(try h.store.load(), pending)
        XCTAssertEqual(h.wire.requests.map { $0.url!.lastPathComponent }, ["titles", "eligible", "list"])
        XCTAssertEqual(h.memory.writeCount, 1)
    }
    func testOverviewNeverReturnsPartialOrStaleSnapshot() async throws {
        let h = try S.Harness()
        h.wire.responses = [try S.success([S.title]), try S.failure("INVOICE_FEATURE_OFF")]
        await S.expect(.rejected("INVOICE_FEATURE_OFF")) { _ = try await h.coordinator().overview() }
        XCTAssertEqual(h.wire.requests.count, 2)
        let stale = try S.Harness()
        stale.wire.responses = [try S.success([S.title]), try S.success([]), try S.success([])]
        stale.wire.afterSend = { if stale.wire.requests.count == 3 { stale.current = nil } }
        await S.expect(.staleSession) { _ = try await stale.coordinator().overview() }
        XCTAssertTrue(stale.memory.values.isEmpty)
    }
    func testOverviewCannotHideCorruptedPendingStoreBehindSuccessfulReads() async throws {
        let h = try S.Harness(); try h.store.save(.init(kind: .cancel, targetID: 51))
        h.memory.values[h.memory.values.keys.first!] = Data("{}".utf8)
        h.wire.responses = [try S.success([S.title]), try S.success([]), try S.success([])]
        await S.expect(.storageUnavailable) { _ = try await h.coordinator().overview() }
        XCTAssertEqual(h.memory.writeCount, 1)
    }
    func testSuccessfulMutationThenReadRejectionIsUnknownForEveryWriteKind() async throws {
        let title = try S.Harness()
        title.wire.responses = [try S.success(S.title), try S.failure("INVOICE_TITLE_NOT_FOUND")]
        await S.expect(.outcomeUnknown) {
            _ = try await title.coordinator().saveTitle(InvoiceLaunchTitleDraft(titleType: "PERSONAL", titleName: "Synthetic title"))
        }
        XCTAssertNotNil(try title.store.load())
        let deletion = try S.Harness()
        deletion.wire.responses = [try S.success(NSNull()), try S.failure("INVOICE_TITLE_NOT_FOUND")]
        await S.expect(.outcomeUnknown) { try await deletion.coordinator().deleteTitle(id: 11) }
        XCTAssertNotNil(try deletion.store.load())
        let cancel = try S.Harness()
        cancel.wire.responses = [try S.success(S.application(status: "CANCELLED")), try S.failure("INVOICE_NOT_FOUND")]
        await S.expect(.outcomeUnknown) { _ = try await cancel.coordinator().cancel(id: 51) }
        XCTAssertNotNil(try cancel.store.load())
    }
    func testUnknownCancellationReadsNonCancelledFinalFactsWithoutUnlocking() async throws {
        for status in ["SUBMITTED", "ISSUED", "REJECTED"] {
            let h = try S.Harness(); h.wire.failNext = true
            await S.expect(.outcomeUnknown) { _ = try await h.coordinator().cancel(id: 51) }
            h.wire.responses = [try S.success(S.application(status: status))]
            await S.expect(.outcomeUnknown) { _ = try await h.coordinator().recover() }
            XCTAssertEqual(try h.store.load()?.targetID, 51)
            XCTAssertEqual(h.wire.requests.map { $0.url!.lastPathComponent }, ["cancel", "detail"])
        }
    }
    func testAcknowledgedTitleSaveRecoversOriginalIDAfterRestartWithoutAnotherWrite() async throws {
        let h = try S.Harness(); h.wire.responses = [try S.success(S.title)]
        let draft = try InvoiceLaunchTitleDraft(titleType: "PERSONAL", titleName: "Synthetic title")
        await S.expect(.outcomeUnknown) { _ = try await h.coordinator().saveTitle(draft) }
        XCTAssertEqual(try h.store.load()?.acknowledgedTitleID, 11)
        XCTAssertEqual(h.wire.requests.map { $0.url!.lastPathComponent }, ["save", "titles"])
        let restarted = try S.Harness(memory: h.memory, captured: S.session(epoch: 2))
        restarted.wire.responses = [try S.success([S.title])]
        let result = try await restarted.coordinator().recover()
        if case .title(let title) = result { XCTAssertEqual(title.id, 11) } else { XCTFail("Expected original acknowledged title") }
        XCTAssertEqual(restarted.wire.requests.map { $0.url!.lastPathComponent }, ["titles"])
        XCTAssertNil(try restarted.store.load())
    }
    func testUnknownEditCannotUseExistingTargetAsProofOfSave() async throws {
        let h = try S.Harness(); h.wire.failNext = true
        let draft = try InvoiceLaunchTitleDraft(id: 11, titleType: "PERSONAL", titleName: "Synthetic title")
        await S.expect(.outcomeUnknown) { _ = try await h.coordinator().saveTitle(draft) }
        XCTAssertNil(try h.store.load()?.acknowledgedTitleID)
        let restarted = try S.Harness(memory: h.memory, captured: S.session(epoch: 2))
        restarted.wire.responses = [try S.success([S.title])]
        await S.expect(.originalReadUnavailable) { _ = try await restarted.coordinator().recover() }
        XCTAssertTrue(restarted.wire.requests.isEmpty)
        await S.expect(.pendingConflict) { _ = try await restarted.coordinator().saveTitle(draft) }
    }
    func testFailedTitleCheckpointDoesNotGuessAcknowledgementFromMemory() async throws {
        let h = try S.Harness(); h.wire.responses = [try S.success(S.title)]
        h.wire.afterSend = { h.memory.failWrite = true }
        await S.expect(.storageUnavailable) {
            _ = try await h.coordinator().saveTitle(InvoiceLaunchTitleDraft(titleType: "PERSONAL", titleName: "Synthetic title"))
        }
        XCTAssertNil(try h.store.load()?.acknowledgedTitleID)
        await S.expect(.originalReadUnavailable) { _ = try await h.coordinator().recover() }
        XCTAssertEqual(h.wire.requests.count, 1)
    }
    func testMissingOrRejectedAcknowledgedTitleReadNeverUnlocksOrWritesAgain() async throws {
        let h = try S.Harness(), pending = InvoiceLaunchPending(kind: .saveTitle)
        try h.store.save(pending); _ = try h.store.checkpointTitle(pending, acknowledgedTitleID: 11)
        var unrelated = S.title; unrelated["id"] = 12
        h.wire.responses = [try S.success([unrelated]), try S.failure("INVOICE_TITLE_NOT_FOUND")]
        await S.expect(.outcomeUnknown) { _ = try await h.coordinator().recover() }
        await S.expect(.outcomeUnknown) { _ = try await h.coordinator().recover() }
        XCTAssertEqual(try h.store.load()?.acknowledgedTitleID, 11)
        XCTAssertEqual(h.wire.requests.map { $0.url!.lastPathComponent }, ["titles", "titles"])
    }
    func testLateAcknowledgedTitleReadCannotClearAnotherSessionsPending() async throws {
        let h = try S.Harness(), pending = InvoiceLaunchPending(kind: .saveTitle)
        try h.store.save(pending); let checkpoint = try h.store.checkpointTitle(pending, acknowledgedTitleID: 11)
        h.wire.responses = [try S.success([S.title])]; h.wire.afterSend = { h.current = nil }
        await S.expect(.outcomeUnknown) { _ = try await h.coordinator().recover() }
        XCTAssertEqual(try h.store.load(), checkpoint)
    }
    func testMalformedDeletionSuccessKeepsOriginalWithoutReadingOrRetrying() async throws {
        for body in [[:] as [String: Any], [] as [Any], "unexpected", true, 0] as [Any] {
            let h = try S.Harness(); h.wire.responses = [try S.success(body)]
            await S.expect(.outcomeUnknown) { try await h.coordinator().deleteTitle(id: 11) }
            XCTAssertEqual(try h.store.load()?.targetID, 11)
            XCTAssertEqual(h.wire.requests.map { $0.url!.lastPathComponent }, ["delete"])
        }
    }
    func testUnknownApplyRecoversOriginalRequestAfterRestartWithoutWrite() async throws {
        let h = try S.Harness(); h.originalReceipts = true; h.wire.failNext = true
        await S.expect(.outcomeUnknown) { _ = try await h.coordinator().apply(h.command()) }
        let restarted = try S.Harness(memory: h.memory, captured: S.session(epoch: 2)); restarted.originalReceipts = true
        var app = S.application(); app["requestId"] = "synthetic-original-request"
        restarted.wire.responses = [try S.success(app)]
        _ = try await restarted.coordinator().recover()
        XCTAssertNil(try restarted.store.load())
        XCTAssertEqual(restarted.wire.requests.map { $0.url!.path }, ["/native/api/invoice/request"])
        let body = try JSONSerialization.jsonObject(with: restarted.wire.requests[0].httpBody!) as! [String: Any]
        XCTAssertEqual(body["requestId"] as? String, "synthetic-original-request"); XCTAssertEqual(body.count, 1)
    }
    func testOriginalApplyMismatchAndNotFoundKeepExactJournal() async throws {
        let h = try S.Harness(); h.originalReceipts = true; h.wire.failNext = true
        await S.expect(.outcomeUnknown) { _ = try await h.coordinator().apply(h.command()) }
        let original = try XCTUnwrap(h.store.load())
        var wrong = S.application(orders: [99]); wrong["requestId"] = "synthetic-original-request"
        for response in [try S.success(wrong), try S.failure("INVOICE_NOT_FOUND")] {
            h.wire.responses = [response]
            await S.expect(.outcomeUnknown) { _ = try await h.coordinator().recover() }
            XCTAssertEqual(try h.store.load(), original)
        }
        let count = h.wire.requests.count
        await S.expect(.pendingConflict) { _ = try await h.coordinator().apply(h.command()) }
        XCTAssertEqual(h.wire.requests.count, count)
    }
    func testOriginalApplyCannotReplaceCheckpointedEntity() async throws {
        let h = try S.Harness(); h.originalReceipts = true
        var app = S.application(); app["requestId"] = "synthetic-original-request"
        h.wire.responses = [try S.success(app)]
        await S.expect(.outcomeUnknown) { _ = try await h.coordinator().apply(h.command()) }
        XCTAssertEqual(try h.store.load()?.applicationID, 51)
        app["id"] = "52"; h.wire.responses = [try S.success(app)]
        await S.expect(.outcomeUnknown) { _ = try await h.coordinator().recover() }
        XCTAssertEqual(try h.store.load()?.applicationID, 51)
    }
    func testOriginalTitleSavePersistsKeyBeforeSendingAndRecoversWithoutPII() async throws {
        let h = try S.Harness(); h.originalReceipts = true; h.wire.failNext = true
        let draft = try InvoiceLaunchTitleDraft(titleType: "COMPANY", titleName: "Synthetic private name", taxNo: "913456789012345678")
        h.wire.beforeSend = { XCTAssertNotNil(try h.store.load()?.titleRequestID) }
        await S.expect(.outcomeUnknown) { _ = try await h.coordinator().saveTitle(draft) }
        let original = try XCTUnwrap(h.store.load()), request = try XCTUnwrap(original.titleRequestID)
        let body = try JSONSerialization.jsonObject(with: h.wire.requests[0].httpBody!) as! [String: Any]
        XCTAssertEqual(body["requestId"] as? String, request); XCTAssertEqual(body["titleName"] as? String, draft.titleName)
        XCTAssertEqual(h.wire.requests[0].url?.path, "/native/api/invoice/titles/save-request")
        let persisted = String(decoding: try XCTUnwrap(h.memory.values.values.first), as: UTF8.self)
        XCTAssertFalse(persisted.contains(draft.titleName)); XCTAssertFalse(persisted.contains("913456789012345678"))
        let restarted = try S.Harness(memory: h.memory, captured: S.session(epoch: 2)); restarted.originalReceipts = true
        restarted.wire.responses = [try S.success(["requestId": request, "titleId": "11", "status": "SAVED"])]
        let result = try await restarted.coordinator().recover()
        if case .titleSaved(let receipt) = result { XCTAssertEqual(receipt.titleId, 11) } else { XCTFail("Expected original receipt") }
        XCTAssertNil(try restarted.store.load())
        XCTAssertEqual(restarted.wire.requests.map { $0.url!.path }, ["/native/api/invoice/titles/request"])
    }
    func testOriginalTitleNotFoundRetainsKeyAndNeverFallsBackToLegacySave() async throws {
        let h = try S.Harness(); h.originalReceipts = true; h.wire.failNext = true
        let draft = try InvoiceLaunchTitleDraft(titleType: "PERSONAL", titleName: "Synthetic title")
        await S.expect(.outcomeUnknown) { _ = try await h.coordinator().saveTitle(draft) }
        let original = try XCTUnwrap(h.store.load())
        h.wire.responses = [try S.failure("INVOICE_NOT_FOUND")]
        await S.expect(.outcomeUnknown) { _ = try await h.coordinator().recover() }
        XCTAssertEqual(try h.store.load(), original)
        h.originalReceipts = false
        await S.expect(.outcomeUnknown) { _ = try await h.coordinator().recover() }
        await S.expect(.pendingConflict) { _ = try await h.coordinator().saveTitle(draft) }
        XCTAssertEqual(h.wire.requests.count, 2); XCTAssertEqual(try h.store.load(), original)
    }
    func testOriginalTitleSuccessUsesReceiptIDThenReadsMaskedTitle() async throws {
        let h = try S.Harness(); h.originalReceipts = true
        h.wire.beforeSend = {
            if h.wire.requests.count == 1 {
                let request = try XCTUnwrap(h.store.load()?.titleRequestID)
                h.wire.responses = [try S.success(["requestId": request, "titleId": "11", "status": "SAVED"]), try S.success([S.title])]
            }
        }
        let draft = try InvoiceLaunchTitleDraft(titleType: "PERSONAL", titleName: "Synthetic title")
        let result = try await h.coordinator().saveTitle(draft)
        XCTAssertEqual(result.id, 11); XCTAssertNil(try h.store.load())
        XCTAssertEqual(h.wire.requests.map { $0.url!.path }, ["/native/api/invoice/titles/save-request", "/native/api/invoice/titles"])
    }
    func testStaleOriginalResponseCannotClearPreviousAccountJournal() async throws {
        let h = try S.Harness(); h.originalReceipts = true; h.wire.failNext = true
        await S.expect(.outcomeUnknown) { _ = try await h.coordinator().apply(h.command()) }
        let original = try XCTUnwrap(h.store.load())
        var app = S.application(); app["requestId"] = "synthetic-original-request"
        h.wire.responses = [try S.success(app)]; h.wire.afterSend = { h.current = try? S.session(account: 8) }
        await S.expect(.outcomeUnknown) { _ = try await h.coordinator().recover() }
        XCTAssertEqual(try h.store.load(), original)
    }

    func testOriginalApplyGrantWithdrawalDoesNotDowngradeToEntityRead() async throws {
        let h = try S.Harness(); h.originalReceipts = true
        var app = S.application(); app["requestId"] = "synthetic-original-request"
        h.wire.responses = [try S.success(app)]
        await S.expect(.outcomeUnknown) { _ = try await h.coordinator().apply(h.command()) }
        let original = try XCTUnwrap(h.store.load()); XCTAssertEqual(original.applicationID, 51)
        let count = h.wire.requests.count; h.originalReceipts = false
        await S.expect(.outcomeUnknown) { _ = try await h.coordinator().recover() }
        XCTAssertEqual(try h.store.load(), original); XCTAssertEqual(h.wire.requests.count, count)
    }

}
