import Foundation
import XCTest
@testable import Questify

// Focused real binding/service/controller reads with in-memory storage and synthetic replies.
// No mutation transport, commerce recovery, StoreKit, installation or protected text is invoked.
@MainActor final class WorkshopPaidInstallReentryTests: XCTestCase {
    private static let base = URL(string: "https://example.test/reentry")!
    private static let target: [String: Any] = ["targetDraftId": 91, "targetRevision": 1, "businessType": "TOPIC",
        "targetPayloadHash": String(repeating: "c", count: 64), "mode": "UNRESOLVED", "destinationKind": "W18_PRIVATE_COMPONENT_ONLY"]
    private static func item(_ fields: [String: Any]? = nil) throws -> WorkshopPurchasedItem {
        try JSONDecoder().decode(WorkshopPurchasedItem.self, from: JSONSerialization.data(withJSONObject: fields ?? WorkshopPurchasedAppFixture.item))
    }
    private static func data(_ fields: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) }
    private static func reply(_ fields: [String: Any]) throws -> (Data, Int) { (try data(["code": 200, "data": fields]), 200) }
    private static func command() throws -> WorkshopPaidInstallCommand {
        try .init(item: item(), target: JSONDecoder().decode(WorkshopPaidInstallTarget.self, from: data(target)),
                  region: "synthetic-region", commercialUse: false, requestID: XCTUnwrap(UUID(uuidString: "00000000-0000-4000-8000-000000000111")))
    }
    private static func outcome(_ command: WorkshopPaidInstallCommand, state: String) throws -> [String: Any] {
        if state == "NOT_FOUND" { return ["schema": "w18-paid-install-outcome-v1", "requestId": command.requestId, "state": state] }
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: command.wireData()) as? [String: Any])
        fields["schema"] = "w18-paid-install-outcome-v1"; fields["state"] = state; fields["mode"] = "UNRESOLVED"
        fields["holdDeadline"] = "2026-10-05T00:05:00Z"; fields["professionalTemplateStatus"] = "MATERIALIZATION_REQUIRED"
        fields["published"] = false; fields["executable"] = false
        fields["ownedDraftId"] = state == "INSTALLED_PRIVATE_DRAFT" ? 101 as Any : NSNull()
        fields["installedAt"] = state == "INSTALLED_PRIVATE_DRAFT" ? "2026-10-05T00:00:01Z" as Any : NSNull()
        return fields
    }
    @MainActor private final class Memory: TemplateAuthoringStorage {
        var values: [String: Data] = [:]
        var writes = 0, removes = 0
        func read(_ key: String) throws -> Data? { values[key] }
        func write(_ data: Data, key: String) throws { writes += 1; values[key] = data }
        func remove(_ key: String) throws { removes += 1; values.removeValue(forKey: key) }
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var overrides: [String: (Data, Int)] = [:]
        var command: WorkshopPaidInstallCommand?
        var state = "NOT_FOUND", paginated = false, pauseNext = false
        var suspended: CheckedContinuation<(Data, Int), Never>?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            let route = try XCTUnwrap(request.url?.lastPathComponent)
            guard ["status", "history", "targets"].contains(route),
                  request.url?.path.contains("/workshop/purchased/install/") == true else {
                XCTFail("Reentry cannot dispatch install, commerce/reconcile, text or another API")
                throw WorkshopPaidInstallIssue.disabled
            }
            if pauseNext { pauseNext = false; return await withCheckedContinuation { suspended = $0 } }
            if let failure = overrides[route] { return failure }
            if route == "status" { return try WorkshopPaidInstallReentryTests.reply(WorkshopPaidInstallReentryTests.outcome(XCTUnwrap(command), state: state)) }
            let paging = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            if route == "history" {
                var rows: [[String: Any]] = []
                if paginated {
                    let original = try XCTUnwrap(command)
                    for index in 1...50 {
                        var fields = try WorkshopPaidInstallReentryTests.outcome(original, state: "PREPARED")
                        fields["requestId"] = String(format: "00000000-0000-4000-8000-%012d", index); rows.append(fields)
                    }
                }
                return try WorkshopPaidInstallReentryTests.reply(["schema": "w18-paid-install-history-v1", "scope": "OWNER_COMMAND_RECEIPTS_ONLY",
                    "licenseId": "w18-paid-11", "checkedAt": "2026-10-05T00:00:00Z", "items": rows,
                    "hasMore": paginated, "nextBeforeCommandKey": paginated ? String(repeating: "f", count: 64) as Any : NSNull()])
            }
            var targets = [WorkshopPaidInstallReentryTests.target]
            if paginated {
                let top = (paging["beforeDraftId"] as? Int64) ?? 151
                targets = (1...50).map { offset in var t = WorkshopPaidInstallReentryTests.target; t["targetDraftId"] = top - Int64(offset); return t }
            }
            return try WorkshopPaidInstallReentryTests.reply(["schema": "w18-paid-install-targets-v1", "scope": "OWNER_DRAFT_METADATA_ONLY",
                "licenseId": "w18-paid-11", "checkedAt": "2026-10-05T00:00:00Z", "items": targets,
                "hasMore": paginated, "nextBeforeDraftId": paginated ? targets.last!["targetDraftId"]! : NSNull()])
        }
        func wait() async {
            for _ in 0..<1_000 { if suspended != nil { break }; await Task.yield() }
            XCTAssertNotNil(suspended)
        }
    }
    @MainActor private final class Harness {
        let binding = WorkshopPaidInstallSessionBinding(), wire = Wire(), memory = Memory()
        var current: RuntimeDependencyContext?, approval: WorkshopPaidInstallApproval?, api: APIConfiguration?
        var unauthorized = 0
        init(seed: Bool = true) throws {
            current = try Self.context(); api = try .init(baseURL: WorkshopPaidInstallReentryTests.base)
            approval = try .init(context: XCTUnwrap(current), expiresAt: .distantFuture)
            if seed {
                let command = try WorkshopPaidInstallReentryTests.command(); wire.command = command
                try store().save(command)
            }
        }
        static func context(account: Int = 7, epoch: UInt64 = 1, namespace: String = "synthetic-reentry",
                            role: String = "player", token: String = "synthetic-token", base: URL? = nil) throws -> RuntimeDependencyContext {
            .init(market: .china, baseURL: base ?? WorkshopPaidInstallReentryTests.base, role: role, session: try .init(accountID: account, epoch: epoch, namespace: namespace, token: token, role: role))
        }
        func store() throws -> WorkshopPaidInstallPendingStore {
            try .init(storage: memory, context: XCTUnwrap(current), licenseId: "w18-paid-11")
        }
        func make(_ item: WorkshopPurchasedItem? = nil) throws -> WorkshopPaidInstallController? {
            binding.make(item: try item ?? WorkshopPaidInstallReentryTests.item(), context: current, approval: approval, api: api,
                transport: wire, storage: memory, currentApproval: { self.approval }, current: { self.current }, onUnauthorized: { _ in self.unauthorized += 1 })
        }
        func opened() async throws -> (WorkshopPaidInstallController, WorkshopPaidInstallAppearance) {
            let controller = try XCTUnwrap(make()), appearance = WorkshopPaidInstallAppearance()
            await (try XCTUnwrap(controller.appear(appearance)))(); return (controller, appearance)
        }
    }
    func testBounded503StatusHistoryTargetsReentryReadsSameOriginalBeforeCollections() async throws {
        for route in ["status", "history", "targets"] {
            for envelope503 in [false, true] {
                let h = try Harness(), before = h.memory.values
                h.wire.overrides[route] = envelope503 ? (try Self.data(["code": 503]), 200) : (Data(), 503)
                let (old, appearance) = try await h.opened()
                XCTAssertEqual(old.phase, .invalidated); XCTAssertNil(old.pending); XCTAssertTrue(old.history.isEmpty)
                XCTAssertTrue(old.targets.isEmpty); XCTAssertEqual(h.memory.values, before); XCTAssertEqual(h.memory.removes, 0)
                old.close(appearance); h.wire.overrides = [:]
                let count = h.wire.requests.count, fresh = try XCTUnwrap(h.make())
                XCTAssertFalse(old === fresh); XCTAssertNotEqual(old.identity, fresh.identity)
                XCTAssertEqual(fresh.phase, .idle); XCTAssertEqual(h.wire.requests.count, count) // Construction does not read or submit.
                let reopened = WorkshopPaidInstallAppearance(); await (try XCTUnwrap(fresh.appear(reopened)))()
                XCTAssertEqual(fresh.phase, .ready); XCTAssertEqual(fresh.pending, h.wire.command); XCTAssertEqual(fresh.outcome?.state, .notFound)
                XCTAssertEqual(h.wire.requests.dropFirst(count).map { $0.url!.lastPathComponent }, ["status", "history", "targets"])
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(h.wire.requests[count].httpBody)) as? [String: Any])
                XCTAssertEqual(body["requestId"] as? String, h.wire.command?.requestId)
                XCTAssertEqual(h.memory.values, before); XCTAssertEqual(h.memory.writes, 1); XCTAssertEqual(h.memory.removes, 0)
                XCTAssertNil(old.appear(WorkshopPaidInstallAppearance())); XCTAssertNil(old.resume(appearance))
            }
        }
    }
    func testResumeAndEachPage503RetireCacheButKeepPendingAcrossReentry() async throws {
        for stage in ["resume", "history", "targets"] {
            let h = try Harness(); h.wire.paginated = stage != "resume"
            let (old, appearance) = try await h.opened(); XCTAssertEqual(old.phase, .ready)
            let before = h.memory.values
            if stage == "resume" {
                old.suspend(appearance); h.wire.overrides["history"] = (Data(), 503)
                await (try XCTUnwrap(old.resume(appearance)))()
            } else if stage == "history" {
                h.wire.overrides["history"] = (Data(), 503)
                await (try XCTUnwrap(old.offerLoad(appearance, beforeHistory: old.nextHistoryCursor)))()
            } else {
                h.wire.overrides["targets"] = (Data(), 503)
                await (try XCTUnwrap(old.offerLoad(appearance, beforeTarget: old.nextTargetCursor)))()
            }
            XCTAssertEqual(old.phase, .invalidated); old.close(appearance); h.wire.overrides = [:]
            let beforeRead = h.wire.requests.count, fresh = try XCTUnwrap(h.make())
            XCTAssertFalse(old === fresh); await (try XCTUnwrap(fresh.appear(WorkshopPaidInstallAppearance())))()
            XCTAssertEqual(fresh.phase, .ready); XCTAssertEqual(fresh.pending?.requestId, h.wire.command?.requestId)
            XCTAssertEqual(h.wire.requests[beforeRead].url?.lastPathComponent, "status"); XCTAssertEqual(h.memory.values, before)
        }
    }
    func testCurrentCacheSurvivesHealthyCloseSuspendAndOrdinaryFailureWithoutReconstruction() async throws {
        let h = try Harness(), first = try XCTUnwrap(h.make())
        XCTAssertTrue(try first === h.make()); let a = WorkshopPaidInstallAppearance(); await (try XCTUnwrap(first.appear(a)))()
        XCTAssertTrue(try first === h.make()); first.suspend(a); XCTAssertTrue(try first === h.make())
        await (try XCTUnwrap(first.resume(a)))(); first.close(a); XCTAssertTrue(try first === h.make())
        h.wire.overrides["status"] = (Data(), 500)
        await (try XCTUnwrap(first.appear(WorkshopPaidInstallAppearance())))()
        XCTAssertEqual(first.phase, .failed); XCTAssertTrue(try first === h.make())
        XCTAssertEqual(try h.store().load(), h.wire.command)
    }
    func testOversizedOrMalformed503DoesNotEnterDisabledInvalidationCase() async throws {
        for reply in [(Data(repeating: 0, count: 524_289), 503), (Data("malformed".utf8), 200)] {
            let h = try Harness(); h.wire.overrides["status"] = reply
            let (c, _) = try await h.opened()
            XCTAssertEqual(c.phase, .failed); XCTAssertEqual(c.issue, .malformed); XCTAssertTrue(try c === h.make())
            XCTAssertEqual(try h.store().load(), h.wire.command); XCTAssertEqual(h.memory.removes, 0)
        }
    }
    func testExplicitStatus503RetiresControllerAndRecoversOriginalWithoutSubmit() async throws {
        for envelope503 in [false, true] {
            let h = try Harness(), (controller, appearance) = try await h.opened()
            let before = h.memory.values, count = h.wire.requests.count
            h.wire.overrides["status"] = envelope503 ? (try Self.data(["code": 503]), 200) : (Data(), 503)
            await (try XCTUnwrap(controller.offerStatus(appearance)))()
            XCTAssertEqual(controller.phase, .invalidated); XCTAssertEqual(controller.issue, .disabled)
            XCTAssertNil(controller.pending); XCTAssertNil(controller.outcome)
            XCTAssertTrue(controller.history.isEmpty); XCTAssertTrue(controller.targets.isEmpty)
            XCTAssertNil(controller.offerStatus(appearance)); XCTAssertNil(controller.resume(appearance))
            XCTAssertNil(controller.appear(WorkshopPaidInstallAppearance()))
            XCTAssertEqual(h.wire.requests.dropFirst(count).map { $0.url!.lastPathComponent }, ["status"])
            XCTAssertEqual(try h.store().load(), h.wire.command)
            XCTAssertEqual(h.memory.values, before); XCTAssertEqual(h.memory.removes, 0)
            controller.close(appearance); h.wire.overrides = [:]
            let beforeRead = h.wire.requests.count, fresh = try XCTUnwrap(h.make())
            XCTAssertFalse(controller === fresh); XCTAssertNotEqual(controller.identity, fresh.identity)
            XCTAssertEqual(fresh.phase, .idle); XCTAssertEqual(h.wire.requests.count, beforeRead)
            await (try XCTUnwrap(fresh.appear(WorkshopPaidInstallAppearance())))()
            XCTAssertEqual(fresh.phase, .ready); XCTAssertEqual(fresh.pending, h.wire.command)
            XCTAssertEqual(fresh.outcome?.state, .notFound)
            XCTAssertEqual(h.wire.requests.dropFirst(beforeRead).map { $0.url!.lastPathComponent }, ["status", "history", "targets"])
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(h.wire.requests[beforeRead].httpBody)) as? [String: Any])
            XCTAssertEqual(body["requestId"] as? String, h.wire.command?.requestId)
            XCTAssertEqual(h.memory.values, before); XCTAssertEqual(h.memory.writes, 1); XCTAssertEqual(h.memory.removes, 0)
        }
    }
    func testMissingExpiredReissuedOrMismatchedContextCannotRecreateOrRead() async throws {
        for variant in 0..<8 {
            let h = try Harness(), old = try XCTUnwrap(h.make()), before = h.memory.values
            switch variant {
            case 0: h.approval = nil
            case 1: h.approval = try .init(context: XCTUnwrap(h.current), expiresAt: .distantPast)
            case 2: h.current = try Harness.context(account: 8)
            case 3: h.current = try Harness.context(epoch: 2)
            case 4: h.current = try Harness.context(role: "merchant")
            case 5: h.current = try Harness.context(token: "synthetic-new-token")
            case 6: h.api = try .init(baseURL: URL(string: "https://other.example.test/reentry")!)
            default: h.current = try Harness.context(namespace: "other")
            }
            XCTAssertNil(try h.make()); XCTAssertEqual(old.phase, .invalidated)
            XCTAssertNil(old.appear(WorkshopPaidInstallAppearance())); XCTAssertTrue(h.wire.requests.isEmpty)
            XCTAssertEqual(h.memory.values, before); XCTAssertEqual(h.memory.removes, 0)
        }
        let h = try Harness(), old = try XCTUnwrap(h.make()); h.approval = try .init(context: XCTUnwrap(h.current), expiresAt: .distantFuture)
        let fresh = try XCTUnwrap(h.make()); XCTAssertFalse(old === fresh); XCTAssertEqual(old.phase, .invalidated)
        XCTAssertTrue(h.wire.requests.isEmpty); XCTAssertEqual(try h.store().load(), h.wire.command)
    }
    func testOwnerBDoesNotInheritAPendingAndAReturnReadsOnlyOriginalAKey() async throws {
        let h = try Harness(), originalContext = try XCTUnwrap(h.current), originalApproval = h.approval, bytes = h.memory.values
        let (a, appearance) = try await h.opened(); a.close(appearance)
        h.current = try Harness.context(account: 8); h.approval = try .init(context: XCTUnwrap(h.current), expiresAt: .distantFuture)
        let b = try XCTUnwrap(h.make()), beforeB = h.wire.requests.count
        await (try XCTUnwrap(b.appear(WorkshopPaidInstallAppearance())))()
        XCTAssertEqual(a.phase, .invalidated); XCTAssertNil(b.pending); XCTAssertNil(b.outcome)
        XCTAssertEqual(h.wire.requests.dropFirst(beforeB).map { $0.url!.lastPathComponent }, ["history", "targets"])
        XCTAssertEqual(h.memory.values, bytes)
        h.current = originalContext; h.approval = originalApproval
        let again = try XCTUnwrap(h.make()), beforeA = h.wire.requests.count
        await (try XCTUnwrap(again.appear(WorkshopPaidInstallAppearance())))()
        XCTAssertFalse(a === again); XCTAssertEqual(b.phase, .invalidated)
        XCTAssertEqual(h.wire.requests[beforeA].url?.lastPathComponent, "status"); XCTAssertEqual(again.pending, h.wire.command)
        XCTAssertEqual(h.memory.values, bytes)
    }
    func testLateInvalidatedStatusCannotAcknowledgePendingOrRepopulateReplacement() async throws {
        let h = try Harness(), old = try XCTUnwrap(h.make()), oldAppearance = WorkshopPaidInstallAppearance()
        h.wire.pauseNext = true
        let task = Task { await (try XCTUnwrap(old.appear(oldAppearance)))() }; await h.wire.wait()
        h.wire.overrides["status"] = (Data(), 503)
        await (try XCTUnwrap(old.offerLoad(oldAppearance)))()
        XCTAssertEqual(old.phase, .invalidated); let bytes = h.memory.values
        h.wire.overrides = [:]; let fresh = try XCTUnwrap(h.make())
        await (try XCTUnwrap(fresh.appear(WorkshopPaidInstallAppearance())))()
        let count = h.wire.requests.count
        let continuation = try XCTUnwrap(h.wire.suspended); h.wire.suspended = nil
        continuation.resume(returning: try Self.reply(Self.outcome(XCTUnwrap(h.wire.command), state: "INSTALLED_PRIVATE_DRAFT")))
        try await task.value
        XCTAssertEqual(old.phase, .invalidated); XCTAssertNil(old.outcome); XCTAssertNil(old.pending)
        XCTAssertEqual(fresh.phase, .ready); XCTAssertEqual(fresh.outcome?.state, .notFound); XCTAssertEqual(fresh.pending, h.wire.command)
        XCTAssertEqual(h.memory.values, bytes); XCTAssertEqual(h.memory.removes, 0); XCTAssertEqual(h.unauthorized, 0)
        XCTAssertEqual(h.wire.requests.count, count)
    }
    func testClosedOrBackgroundOldActionDoesNotReviveAndHealthyCacheStillReuses() async throws {
        for background in [false, true] {
            let h = try Harness(), controller = try XCTUnwrap(h.make()), a = WorkshopPaidInstallAppearance()
            let queued = try XCTUnwrap(controller.appear(a))
            if background { controller.suspend(a) } else { controller.close(a) }
            await queued(); XCTAssertTrue(h.wire.requests.isEmpty); XCTAssertTrue(try controller === h.make())
            XCTAssertEqual(try h.store().load(), h.wire.command)
            if background { await (try XCTUnwrap(controller.resume(a)))() }
            else { await (try XCTUnwrap(controller.appear(WorkshopPaidInstallAppearance())))() }
            XCTAssertEqual(controller.phase, .ready); XCTAssertEqual(controller.pending, h.wire.command)
        }
    }
    func testFullItemReplacementCreatesNewControllerButNeverRebuildsSavedCommand() async throws {
        let h = try Harness(), old = try XCTUnwrap(h.make()), before = h.memory.values
        var changed = WorkshopPurchasedAppFixture.item; changed["contentHash"] = String(repeating: "d", count: 64)
        let fresh = try XCTUnwrap(h.make(Self.item(changed)))
        XCTAssertFalse(old === fresh); XCTAssertEqual(old.phase, .invalidated)
        await (try XCTUnwrap(fresh.appear(WorkshopPaidInstallAppearance())))()
        XCTAssertEqual(fresh.phase, .failed); XCTAssertEqual(fresh.issue, .storageUnavailable)
        XCTAssertTrue(h.wire.requests.isEmpty); XCTAssertEqual(h.memory.values, before); XCTAssertEqual(h.memory.writes, 1)
    }
    func testExactInstalledReceiptAloneAcknowledgesAndProtectedTextStillNeedsSeparateGrant() async throws {
        let h = try Harness(); h.wire.state = "INSTALLED_PRIVATE_DRAFT"
        let (controller, a) = try await h.opened()
        XCTAssertEqual(controller.phase, .installed); XCTAssertNil(controller.pending); XCTAssertEqual(h.memory.removes, 1)
        let outcome = try XCTUnwrap(controller.outcome), reference = try XCTUnwrap(controller.installedTextReference(outcome, appearance: a))
        let textBinding = WorkshopPaidInstalledTextSessionBinding(), context = try XCTUnwrap(h.current)
        let count = h.wire.requests.count
        XCTAssertNil(textBinding.make(reference: reference, context: context, approval: nil, api: h.api, transport: h.wire,
            currentApproval: { nil }, current: { h.current }, onUnauthorized: { _ in XCTFail() }))
        XCTAssertEqual(h.wire.requests.count, count)
        controller.close(a); XCTAssertNil(controller.installedTextReference(outcome, appearance: a))
        XCTAssertEqual(h.wire.requests.count, count)
    }
}
