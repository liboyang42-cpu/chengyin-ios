import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class NativeChannelChainLaunchTests: XCTestCase {
    func testDigestUsesUTF8LengthsAndOriginalIntentForAllOperations() async throws {
        let create = command(.create, title: "接龙")
        XCTAssertEqual(create.digest, "be244ea2d08f18010f838e3438a2ce9278dac7f23aa3715861f46cd4e001d33c")
        let join = command(.join, content: "a:b👋")
        XCTAssertEqual(join.digest, "5f32063927760dbdf1a9bb21202cdd5bb6eb9170e9068be64e30134ef1c0c306")
        for operation in operations {
            let original = command(operation)
            try original.validate()
            let decoded = try JSONDecoder().decode(NativeChannelChainCommand.self, from: JSONEncoder().encode(original))
            XCTAssertEqual(decoded, original)
            XCTAssertEqual(decoded.digest, original.digest)
            XCTAssertEqual(original.path, "api/im/chain/" + operation.rawValue.lowercased())
        }
        XCTAssertEqual(Set(operations.map { command($0).digest }).count, 4)
        XCTAssertNotEqual(command(.join, content: "é").digest, command(.join, content: "e\u{301}").digest)
    }

    func testEveryOperationRecoversAppliedReceiptAfterTimeoutAndRestartWithoutAnotherPost() async throws {
        for operation in operations {
            let h = try LaunchChainHarness(operation)
            let first = try h.flow()
            let original = try await h.submit(first)
            XCTAssertEqual(first.phase, .unknown)
            XCTAssertEqual(first.pending, original)
            XCTAssertFalse(h.storage.rows.isEmpty)
            first.deactivate()
            h.wire.applied = true
            let restarted = try h.flow()
            await restarted.activate(current: { h.live })
            XCTAssertNil(restarted.pending)
            XCTAssertEqual(restarted.lastConfirmedRequest?.requestID, original.requestId)
            XCTAssertEqual(restarted.lastConfirmedRequest?.operation, operation)
            XCTAssertTrue(h.storage.rows.isEmpty)
            XCTAssertEqual(h.wire.posts.count, 1)
            XCTAssertEqual(h.wire.receiptIDs, [original.requestId])
            XCTAssertEqual(h.wire.events.filter { $0 != "info:0" }, ["POST:" + operation.rawValue, "receipt"])
        }
    }

    func testMissingReceiptRequiresExplicitRetryOfSameBytesForEveryOperation() async throws {
        for operation in operations {
            let h = try LaunchChainHarness(operation)
            let first = try h.flow()
            let original = try await h.submit(first)
            first.deactivate()
            h.wire.receiptState = "NOT_FOUND"
            let restarted = try h.flow()
            await restarted.activate(current: { h.live })
            XCTAssertEqual(restarted.pending, original)
            XCTAssertEqual(h.wire.posts.count, 1)
            h.wire.timeout = false
            await restarted.retryOriginal()
            XCTAssertEqual(h.wire.posts.count, 2)
            XCTAssertEqual(h.wire.posts.first, h.wire.posts.last)
            XCTAssertEqual(h.wire.receiptIDs, [original.requestId, original.requestId])
            XCTAssertEqual(Array(h.wire.events.suffix(2)), ["receipt", "POST:" + operation.rawValue])
            XCTAssertNil(restarted.pending)
            XCTAssertEqual(restarted.lastConfirmedRequest?.requestID, original.requestId)
        }
    }

    func testPendingReceiptNeverResendsOrClearsJournal() async throws {
        for operation in operations {
            let h = try LaunchChainHarness(operation)
            let flow = try h.flow()
            let original = try await h.submit(flow)
            h.wire.receiptState = "PENDING"
            await flow.retryOriginal()
            XCTAssertEqual(flow.phase, .unknown)
            XCTAssertEqual(flow.pending, original)
            XCTAssertEqual(h.wire.posts.count, 1)
            XCTAssertFalse(h.storage.rows.isEmpty)
        }
    }

    func testMismatchedReceiptsCannotSettleAnyOperation() async throws {
        let mutations: [(inout [String: Any]) -> Void] = [
            { $0["requestId"] = "00000000-0000-0000-0000-000000000002" },
            { $0["requestHash"] = String(repeating: "0", count: 64) },
            { $0["operation"] = "OTHER" }, { $0["actorId"] = "12" }, { $0["conversationId"] = "43" }
        ]
        for operation in operations {
            for mutate in mutations {
                let h = try LaunchChainHarness(operation)
                let first = try h.flow()
                let original = try await h.submit(first)
                first.deactivate()
                h.wire.applied = true; h.wire.mutateReceipt = mutate
                let restarted = try h.flow()
                await restarted.activate(current: { h.live })
                XCTAssertEqual(restarted.pending, original)
                XCTAssertNil(restarted.lastConfirmedRequest)
                XCTAssertFalse(h.storage.rows.isEmpty)
                XCTAssertEqual(h.wire.posts.count, 1)
            }
        }
    }

    func testChangedPersistedRequestIDBlocksRetryEvenWithSameDigest() async throws {
        let h = try LaunchChainHarness(.create)
        let flow = try h.flow()
        let original = try await h.submit(flow)
        let key = try XCTUnwrap(h.storage.rows.keys.first)
        var record = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(h.storage.rows[key])) as? [String: Any])
        var saved = try XCTUnwrap(record["command"] as? [String: Any])
        saved["requestId"] = "00000000-0000-0000-0000-000000000002"
        record["command"] = saved
        h.storage.rows[key] = try JSONSerialization.data(withJSONObject: record)
        h.wire.receiptState = "NOT_FOUND"; h.wire.timeout = false
        await flow.retryOriginal()
        XCTAssertEqual(flow.pending, original)
        XCTAssertEqual(flow.phase, .unknown)
        XCTAssertEqual(h.wire.posts.count, 1)
    }

    func testReceiptActiveCountOutsideWireIntegerRangeRetainsOriginalIntent() async throws {
        let h = try LaunchChainHarness(.join)
        let first = try h.flow(); let original = try await h.submit(first)
        first.deactivate(); h.wire.applied = true
        h.wire.mutateReceipt = { value in
            var result = value["result"] as! [String: Any]
            result["activeCount"] = Int(Int32.max) + 1; value["result"] = result
        }
        let restarted = try h.flow(); await restarted.activate(current: { h.live })
        XCTAssertEqual(restarted.pending, original)
        XCTAssertNil(restarted.lastConfirmedRequest)
        XCTAssertFalse(h.storage.rows.isEmpty); XCTAssertEqual(h.wire.posts.count, 1)
    }

    func testWithdrawClearsOldContentAndRejectsContentInWithdrawnRows() async throws {
        let h = try LaunchChainHarness(.withdraw)
        let flow = try h.flow()
        await flow.activate(current: { h.live })
        XCTAssertEqual(flow.entries.first?.content, "original content")
        h.wire.timeout = false
        flow.prepareWithdraw(); await flow.confirm()
        XCTAssertNil(flow.page); XCTAssertTrue(flow.entries.isEmpty)
        XCTAssertNil(flow.pending); XCTAssertTrue(h.storage.rows.isEmpty)
        await flow.refresh()
        XCTAssertEqual(flow.entries.first?.status, "WITHDRAWN")
        XCTAssertNil(flow.entries.first?.content)
        h.wire.mutatePage = { page, _ in
            var rows = page["list"] as! [[String: Any]]
            rows[0]["content"] = "withdrawn secret"
            page["list"] = rows
        }
        await flow.refresh()
        XCTAssertTrue(flow.readFailed); XCTAssertNil(flow.page); XCTAssertTrue(flow.entries.isEmpty)
    }

    func testPersonalRowCannotDisagreeWithWithdrawnMine() async throws {
        let h = try LaunchChainHarness(.withdraw)
        h.wire.mutatePage = { page, _ in
            var mine = page["mine"] as! [String: Any]
            mine["status"] = "WITHDRAWN"; mine.removeValue(forKey: "content")
            page["mine"] = mine
        }
        let flow = try h.flow(); await flow.activate(current: { h.live })
        XCTAssertTrue(flow.readFailed); XCTAssertNil(flow.page); XCTAssertTrue(flow.entries.isEmpty)
    }

    func testPaginationUsesServerPositionAndRestartsOnVersionChange() async throws {
        let h = try LaunchChainHarness(.join)
        h.wire.mutatePage = { page, cursor in
            let fresh = cursor != "0"
            var chain = page["chain"] as! [String: Any]
            chain["version"] = fresh ? "2" : "1"
            page["chain"] = chain
            page["list"] = [launchEntry(id: fresh ? "99" : "90", member: fresh ? "13" : "12", position: fresh ? "20" : "10")]
            page["hasMore"] = !fresh
            if !fresh { page["nextCursor"] = "10" }
        }
        let flow = try h.flow(); await flow.activate(current: { h.live })
        XCTAssertEqual(flow.entries.map(\.id), ["90"])
        // The restart response must also be the new snapshot.
        h.wire.mutatePage = { page, cursor in
            var chain = page["chain"] as! [String: Any]; chain["version"] = "2"; page["chain"] = chain
            page["list"] = [launchEntry(id: cursor == "0" ? "4" : "99", member: "13", position: cursor == "0" ? "3" : "20")]
        }
        await flow.more()
        XCTAssertEqual(Array(h.wire.events.suffix(2)), ["info:10", "info:0"])
        XCTAssertEqual(flow.entries.map(\.id), ["4"])
        XCTAssertEqual(flow.page?.chain.version, "2")
        XCTAssertFalse(flow.readFailed)
    }

    func testSameVersionPaginationRejectsDuplicateMembersAndIDs() async throws {
        for duplicateID in [false, true] {
            let h = try LaunchChainHarness(.join)
            h.wire.mutatePage = { page, cursor in
                page["list"] = [launchEntry(id: cursor == "0" || duplicateID ? "90" : "91", member: cursor == "0" || !duplicateID ? "12" : "13", position: cursor == "0" ? "10" : "20")]
                page["hasMore"] = cursor == "0"
                if cursor == "0" { page["nextCursor"] = "10" }
            }
            let flow = try h.flow(); await flow.activate(current: { h.live }); await flow.more()
            XCTAssertTrue(flow.readFailed); XCTAssertTrue(flow.entries.isEmpty); XCTAssertNil(flow.page)
        }
    }

    func testLaterPageCannotKeepAnEarlierActiveCopyOfWithdrawnMine() async throws {
        let h = try LaunchChainHarness(.withdraw)
        h.wire.mutatePage = { page, cursor in
            if cursor == "0" {
                page["hasMore"] = true; page["nextCursor"] = "1"
            } else {
                page["list"] = [launchEntry(id: "10", member: "12", position: "2")]
                page["mine"] = launchEntry(withdrawn: true)
            }
        }
        let flow = try h.flow(); await flow.activate(current: { h.live })
        XCTAssertEqual(flow.entries.first?.content, "original content")
        await flow.more()
        XCTAssertTrue(flow.readFailed); XCTAssertNil(flow.page); XCTAssertTrue(flow.entries.isEmpty)
    }

    func testValidPaginationAppendsAndTerminalPageDoesNotFetchAgain() async throws {
        let h = try LaunchChainHarness(.join)
        h.wire.mutatePage = { page, cursor in
            page["list"] = [launchEntry(id: cursor == "0" ? "90" : "4", member: cursor == "0" ? "12" : "13", position: cursor == "0" ? "10" : "20")]
            page["hasMore"] = cursor == "0"
            if cursor == "0" { page["nextCursor"] = "10" }
        }
        let flow = try h.flow(); await flow.activate(current: { h.live }); await flow.more()
        XCTAssertEqual(flow.entries.map(\.id), ["90", "4"])
        let calls = h.wire.events.count; await flow.more(); XCTAssertEqual(h.wire.events.count, calls)
    }

    func testInvalidCursorAndBackwardsPositionsClearPagination() async throws {
        for invalidCursor in [false, true] {
            let h = try LaunchChainHarness(.join)
            h.wire.mutatePage = { page, cursor in
                page["list"] = [launchEntry(id: cursor == "0" ? "90" : "91", member: "12", position: "10")]
                page["hasMore"] = cursor == "0"
                if cursor == "0" { page["nextCursor"] = invalidCursor ? "11" : "10" }
            }
            let flow = try h.flow(); await flow.activate(current: { h.live }); await flow.more()
            XCTAssertTrue(flow.readFailed); XCTAssertNil(flow.page); XCTAssertTrue(flow.entries.isEmpty)
        }
    }

    func testJournalContextMustExactlyMatchCapturedServiceContext() async throws {
        let h = try LaunchChainHarness(.create); let service = try h.service()
        let variants: [RuntimeDependencyContext] = [
            .init(market: .unitedStates, baseURL: h.context.baseURL, role: "player", session: h.context.session),
            .init(market: .china, baseURL: URL(string: "https://other.example.com")!, role: "player", session: h.context.session),
            .init(market: .china, baseURL: h.context.baseURL, role: "merchant", session: h.context.session),
            .init(market: .china, baseURL: h.context.baseURL, role: "player", session: try .init(accountID: 11, epoch: 2, namespace: "CN:chain-launch", token: "fixture-token")),
            .init(market: .china, baseURL: h.context.baseURL, role: "player", session: try .init(accountID: 11, epoch: 1, namespace: "CN:other", token: "fixture-token")),
            .init(market: .china, baseURL: h.context.baseURL, role: "player", session: try .init(accountID: 11, epoch: 1, namespace: "CN:chain-launch", token: "rotated-fixture-token"))
        ]
        for context in variants {
            XCTAssertThrowsError(try NativeChannelChainFlow(service: service, context: context, storage: h.storage, reference: nil))
        }
        XCTAssertTrue(h.wire.events.isEmpty); XCTAssertTrue(h.storage.rows.isEmpty)
    }

    func testPageRevokedWhileReadingNeverBecomesVisible() async throws {
        let h = try LaunchChainHarness(.withdraw)
        h.wire.beforeResponse = { _ in h.denied.insert("api/im/chain/info") }
        let flow = try h.flow(); await flow.activate(current: { h.live })
        XCTAssertNil(flow.page); XCTAssertTrue(flow.entries.isEmpty); XCTAssertTrue(flow.readFailed)
        XCTAssertFalse(flow.canWithdraw); XCTAssertFalse(flow.canClose)
    }

    func testWriteGrantRevokedAfterDispatchRetainsExactIntentUntilReceiptRecovery() async throws {
        for operation in operations {
            let h = try LaunchChainHarness(operation); let flow = try h.flow()
            h.wire.timeout = false
            h.wire.beforeResponse = { request in
                if request.httpMethod == "POST" { h.denied.insert("api/im/chain/" + operation.rawValue.lowercased()) }
            }
            let original = try await h.submit(flow)
            XCTAssertEqual(flow.phase, .unknown); XCTAssertEqual(flow.pending, original)
            XCTAssertNil(flow.lastConfirmedRequest); XCTAssertFalse(h.storage.rows.isEmpty)
            h.wire.beforeResponse = nil
            // The write grant stays closed. An applied original receipt is still readable.
            await flow.recover()
            XCTAssertNil(flow.pending); XCTAssertEqual(flow.lastConfirmedRequest?.requestID, original.requestId)
            XCTAssertEqual(h.wire.posts.count, 1); XCTAssertTrue(h.storage.rows.isEmpty)
        }
    }

    func testReceiptGrantRevokedDuringReadDoesNotSettleJournal() async throws {
        let h = try LaunchChainHarness(.create); let flow = try h.flow()
        let original = try await h.submit(flow)
        h.wire.beforeResponse = { request in
            if request.url?.path.hasSuffix("/interaction/request") == true { h.denied.insert("api/im/interaction/request") }
        }
        await flow.recover()
        XCTAssertEqual(flow.pending, original); XCTAssertEqual(flow.phase, .unknown)
        XCTAssertNil(flow.lastConfirmedRequest); XCTAssertFalse(h.storage.rows.isEmpty)
        h.denied.removeAll(); h.wire.beforeResponse = nil
        await flow.recover()
        XCTAssertEqual(flow.lastConfirmedRequest?.requestID, original.requestId)
        XCTAssertTrue(h.storage.rows.isEmpty); XCTAssertEqual(h.wire.posts.count, 1)
    }

    func testReactivationDuringSuspendedReadStartsFreshAndIgnoresOldResult() async throws {
        let h = try LaunchChainHarness(.withdraw); let flow = try h.flow(); let barrier = LaunchChainBarrier()
        var reads = 0
        h.wire.mutatePage = { page, _ in
            reads += 1; var chain = page["chain"] as! [String: Any]
            chain["title"] = reads == 1 ? "old visit" : "current visit"; page["chain"] = chain
        }
        h.wire.beforeResponse = { _ in if !barrier.entered { await barrier.pause() } }
        let old = Task { await flow.activate(current: { h.live }) }
        await barrier.waitUntilEntered(); XCTAssertTrue(flow.busy)
        await flow.activate(current: { h.live })
        XCTAssertFalse(flow.busy); XCTAssertEqual(flow.page?.chain.title, "current visit")
        barrier.resume(); await old.value
        XCTAssertFalse(flow.busy); XCTAssertEqual(flow.page?.chain.title, "current visit")
        XCTAssertEqual(reads, 2)
    }

    func testReactivationDiscardsUnconfirmedReview() async throws {
        let h = try LaunchChainHarness(.join); let flow = try h.flow()
        await flow.activate(current: { h.live }); flow.prepareJoin(content: "original content")
        XCTAssertNotNil(flow.review)
        await flow.activate(current: { h.live })
        XCTAssertNil(flow.review); XCTAssertEqual(flow.phase, .idle)
        XCTAssertEqual(h.wire.events, ["info:0", "info:0"]); XCTAssertTrue(h.wire.posts.isEmpty)
    }

    func testSupersededActivationCannotRefreshTheNewVisitAfterReceiptReturns() async throws {
        let h = try LaunchChainHarness(.create); let first = try h.flow()
        let original = try await h.submit(first); first.deactivate()
        let flow = try h.flow(); let barrier = LaunchChainBarrier()
        h.wire.beforeResponse = { request in
            if request.url?.path.hasSuffix("/interaction/request") == true, !barrier.entered { await barrier.pause() }
        }
        let old = Task { await flow.activate(current: { h.live }) }
        await barrier.waitUntilEntered()
        await flow.activate(current: { h.live })
        XCTAssertEqual(flow.lastConfirmedRequest?.requestID, original.requestId)
        XCTAssertFalse(flow.busy)
        let calls = h.wire.events.count
        barrier.resume(); await old.value
        XCTAssertEqual(h.wire.events.count, calls)
        XCTAssertEqual(h.wire.events.filter { $0 == "info:0" }.count, 1)
        XCTAssertEqual(h.wire.posts.count, 1)
    }

    func testFailedConfirmationReadClearsOldRosterWithoutPosting() async throws {
        let h = try LaunchChainHarness(.withdraw); let flow = try h.flow()
        await flow.activate(current: { h.live }); XCTAssertFalse(flow.entries.isEmpty)
        flow.prepareWithdraw()
        h.wire.beforeResponse = { _ in throw URLError(.networkConnectionLost) }
        await flow.confirm()
        XCTAssertNil(flow.page); XCTAssertTrue(flow.entries.isEmpty); XCTAssertNil(flow.review)
        XCTAssertTrue(flow.readFailed); XCTAssertEqual(flow.phase, .failed)
        XCTAssertTrue(h.wire.posts.isEmpty); XCTAssertTrue(h.storage.rows.isEmpty)
    }

    func testExplicitRefreshAfterReadGrantClosureClearsCachedRoster() async throws {
        let h = try LaunchChainHarness(.withdraw); let flow = try h.flow()
        await flow.activate(current: { h.live }); XCTAssertFalse(flow.entries.isEmpty)
        let calls = h.wire.events.count; h.denied.insert("api/im/chain/info")
        await flow.refresh()
        XCTAssertNil(flow.page); XCTAssertTrue(flow.entries.isEmpty); XCTAssertTrue(flow.readFailed)
        XCTAssertEqual(h.wire.events.count, calls); XCTAssertFalse(flow.canWithdraw)
    }

    func testReadGrantClosureDuringReviewClearsRosterAndReview() async throws {
        let h = try LaunchChainHarness(.withdraw); let flow = try h.flow()
        await flow.activate(current: { h.live }); flow.prepareWithdraw(); XCTAssertNotNil(flow.review)
        h.denied.insert("api/im/chain/info"); await flow.refresh()
        XCTAssertNil(flow.review); XCTAssertNil(flow.page); XCTAssertTrue(flow.entries.isEmpty)
        XCTAssertTrue(flow.readFailed); XCTAssertTrue(h.wire.posts.isEmpty)
    }

    func testCreateReviewCannotDispatchAfterRequiredReadGrantCloses() async throws {
        let h = try LaunchChainHarness(.create); let flow = try h.flow()
        await flow.activate(current: { h.live }); flow.prepareCreate(title: "接龙", maxSlots: 0, deadline: nil)
        XCTAssertNotNil(flow.review); h.denied.insert("api/im/chain/info")
        await flow.confirm()
        XCTAssertTrue(h.wire.posts.isEmpty); XCTAssertTrue(h.storage.rows.isEmpty)
        XCTAssertNil(flow.review); XCTAssertNil(flow.pending); XCTAssertEqual(flow.phase, .failed)
    }

    func testFreshConfirmationRechecksRecoveryGrantBeforeSavingAndPosting() async throws {
        let h = try LaunchChainHarness(.withdraw); let flow = try h.flow()
        await flow.activate(current: { h.live }); flow.prepareWithdraw()
        h.wire.beforeResponse = { _ in h.denied.insert("api/im/interaction/request") }
        await flow.confirm()
        XCTAssertTrue(h.wire.posts.isEmpty); XCTAssertTrue(h.storage.rows.isEmpty)
        XCTAssertNil(flow.review); XCTAssertNil(flow.pending); XCTAssertEqual(flow.phase, .failed)
    }

    func testCancelledOrRetiredWriteClosesVisitButPreservesDurableOriginalForRestart() async throws {
        for cancel in [false, true] {
            let h = try LaunchChainHarness(.create); let flow = try h.flow(); let barrier = LaunchChainBarrier()
            await flow.activate(current: { h.live }); flow.prepareCreate(title: "接龙", maxSlots: 0, deadline: nil)
            let original = try XCTUnwrap(flow.review); h.wire.timeout = false
            h.wire.beforeResponse = { _ in await barrier.pause() }
            let task = Task { await flow.confirm() }
            await barrier.waitUntilEntered()
            if cancel { task.cancel() } else { h.live = false }
            barrier.resume(); await task.value
            XCTAssertEqual(flow.phase, .closed); XCTAssertFalse(flow.busy)
            XCTAssertNil(flow.page); XCTAssertTrue(flow.entries.isEmpty); XCTAssertNil(flow.pending)
            XCTAssertFalse(h.storage.rows.isEmpty); XCTAssertNil(flow.lastConfirmedRequest)
            h.live = true; h.wire.beforeResponse = nil
            let restarted = try h.flow(); await restarted.activate(current: { h.live })
            XCTAssertEqual(restarted.lastConfirmedRequest?.requestID, original.requestId)
            XCTAssertEqual(h.wire.posts.count, 1); XCTAssertTrue(h.storage.rows.isEmpty)
        }
    }

    private var operations: [NativeChannelChainCommand.Operation] { [.create, .join, .withdraw, .close] }
    private func command(_ operation: NativeChannelChainCommand.Operation, title: String = "接龙", content: String = "a:b👋") -> NativeChannelChainCommand {
        .init(requestId: "00000000-0000-0000-0000-000000000001", conversationId: "42", operation: operation,
              chainId: operation == .create ? nil : "7", title: operation == .create ? title : nil,
              maxSlots: operation == .create ? 0 : nil, deadlineAt: nil, content: operation == .join ? content : nil)
    }
}

private func launchEntry(id: String = "9", member: String = "11", position: String = "1", withdrawn: Bool = false) -> [String: Any] {
    var entry: [String: Any] = ["id": id, "chainId": "7", "memberId": member, "position": position, "version": "1", "status": withdrawn ? "WITHDRAWN" : "ACTIVE"]
    if !withdrawn { entry["content"] = "original content" }
    return entry
}

@MainActor private final class LaunchChainStorage: ProjectEditDataStorage {
    var rows: [String: Data] = [:]
    func read(_ key: String) throws -> Data? { rows[key] }
    func write(_ data: Data, key: String) throws { rows[key] = data }
    func remove(_ key: String) throws { rows[key] = nil }
}

@MainActor private final class LaunchChainWire: HTTPTransport {
    let operation: NativeChannelChainCommand.Operation
    var timeout = true, applied = false
    var receiptState = "APPLIED"
    var posts: [Data] = [], receiptIDs: [String] = [], events: [String] = []
    var original: NativeChannelChainCommand?
    var mutateReceipt: ((inout [String: Any]) -> Void)?
    var mutatePage: ((inout [String: Any], String) -> Void)?
    var beforeResponse: ((URLRequest) async throws -> Void)?
    init(_ operation: NativeChannelChainCommand.Operation) { self.operation = operation }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let components = try XCTUnwrap(URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "fixture-token")
        XCTAssertFalse(request.httpShouldHandleCookies)
        var value: [String: Any]
        if request.httpMethod == "POST" {
            let data = try XCTUnwrap(request.httpBody)
            let command = try JSONDecoder().decode(NativeChannelChainCommand.self, from: data)
            try command.validate()
            XCTAssertEqual(command.operation, operation)
            XCTAssertTrue(components.path.hasSuffix(command.path))
            events.append("POST:" + command.operation.rawValue); posts.append(data); original = command
            if timeout { throw URLError(.timedOut) }
            applied = true; value = receipt(command, state: "APPLIED")
        } else if components.path.hasSuffix("/interaction/request") {
            let command = try XCTUnwrap(original)
            XCTAssertEqual(query["conversation_id"], "42")
            receiptIDs.append(try XCTUnwrap(query["request_id"])); events.append("receipt")
            value = receipt(command, state: receiptState); mutateReceipt?(&value)
        } else {
            XCTAssertTrue(components.path.hasSuffix("/chain/info"))
            XCTAssertEqual(query["conversation_id"], "42"); XCTAssertEqual(query["chain_id"], "7"); XCTAssertEqual(query["limit"], "50")
            let cursor = try XCTUnwrap(query["cursor"]); events.append("info:" + cursor)
            value = page(); mutatePage?(&value, cursor)
        }
        let data = try JSONSerialization.data(withJSONObject: ["code": 200, "data": value])
        try await beforeResponse?(request)
        return (data, 200)
    }
    private func receipt(_ command: NativeChannelChainCommand, state: String) -> [String: Any] {
        var value: [String: Any] = ["source": "original-channel-chain-request-v1", "actorId": "11", "conversationId": "42", "requestId": command.requestId, "state": state]
        guard state != "NOT_FOUND" else { return value }
        value["operation"] = command.operation.rawValue; value["requestHash"] = command.digest
        guard state == "APPLIED" else { return value }
        value["resultRedacted"] = false
        var result: [String: Any] = ["chainId": "7", "messageId": "8", "creatorMemberId": "11", "chainVersion": operation == .create ? "1" : "2", "status": operation == .close ? "CLOSED" : "OPEN", "activeCount": operation == .join ? 1 : 0]
        if operation == .join || operation == .withdraw { result["entry"] = launchEntry(withdrawn: operation == .withdraw) }
        value["result"] = result; return value
    }
    private func page() -> [String: Any] {
        let closed = applied && operation == .close
        let hasMine = operation == .withdraw || (applied && operation == .join)
        let withdrawn = applied && operation == .withdraw
        let chain: [String: Any] = ["id": "7", "conversationId": "42", "messageId": "8", "creatorMemberId": "11", "title": "接龙", "status": closed ? "CLOSED" : "OPEN", "version": applied ? "2" : "1", "maxSlots": 0, "activeCount": hasMine && !withdrawn ? 1 : 0, "accepting": !closed, "canParticipate": true, "canClose": !closed]
        var value: [String: Any] = ["source": "original-channel-chain-v1", "chain": chain, "list": hasMine ? [launchEntry(withdrawn: withdrawn)] : [], "hasMore": false]
        if hasMine { value["mine"] = launchEntry(withdrawn: withdrawn) }
        return value
    }
}

@MainActor private final class LaunchChainHarness {
    let context: RuntimeDependencyContext
    let operation: NativeChannelChainCommand.Operation
    let wire: LaunchChainWire
    let storage = LaunchChainStorage()
    var live = true
    var denied: Set<String> = []
    init(_ operation: NativeChannelChainCommand.Operation) throws {
        self.operation = operation; wire = LaunchChainWire(operation)
        context = .init(market: .china, baseURL: URL(string: "https://example.com")!, role: "player", session: try .init(accountID: 11, epoch: 1, namespace: "CN:chain-launch", token: "fixture-token"))
    }
    func flow() throws -> NativeChannelChainFlow {
        let service = try service()
        let reference = operation == .create ? nil : try NativeChannelChainReference(chainID: "7", conversationID: "42", messageID: "8", creatorID: "11")
        return try .init(service: service, context: context, storage: storage, reference: reference)
    }
    func service() throws -> NativeChannelChainService {
        try NativeChannelChainService(context: context, conversationID: "42", transport: wire,
            permits: { _, path in !self.denied.contains(path) }, current: { self.live }, unauthorized: {})
    }
    func submit(_ flow: NativeChannelChainFlow) async throws -> NativeChannelChainCommand {
        await flow.activate(current: { self.live })
        switch operation {
        case .create: flow.prepareCreate(title: "接龙", maxSlots: 0, deadline: nil)
        case .join: flow.prepareJoin(content: "original content")
        case .withdraw: flow.prepareWithdraw()
        case .close: flow.prepareClose()
        }
        let original = try XCTUnwrap(flow.review)
        await flow.confirm(); return original
    }
}

@MainActor private final class LaunchChainBarrier {
    private(set) var entered = false
    private var suspended: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    func pause() async {
        entered = true; observer?.resume(); observer = nil
        await withCheckedContinuation { suspended = $0 }
    }
    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { observer = $0 }
    }
    func resume() { suspended?.resume(); suspended = nil }
}
