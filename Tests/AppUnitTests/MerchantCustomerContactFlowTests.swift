import XCTest
@testable import Questify

@MainActor final class MerchantCustomerContactFlowTests: XCTestCase {
    private func fields(merchant: Int = 610, sensitive: Bool = true) -> MerchantBusinessObject {
        ["active": .bool(true), "merchant": .object(["id": .int(merchant)]), "roleCode": .string("MERCHANT_MANAGER"),
         "permissions": .array((["merchant:crm:read"] + (sensitive ? ["merchant:crm:sensitive:read"] : [])).map(MerchantBusinessValue.string))]
    }
    private func snapshot(phone: String = "138****0000", sensitive: Bool = true, customer: Int = 61001) throws -> MerchantBusinessSnapshot {
        let row: MerchantBusinessObject = ["customerMemberId": .int(customer), "displayName": .string("Synthetic customer"),
            "arrivedCount": .int(0), "pendingCount": .int(0), "refundedCount": .int(0), "paidAmount": .null, "phone": .string(phone)]
        return try .init(access: .init(fields(sensitive: sensitive)), document: .init(query: .customers(.init()), payload: .object(["total": .int(1), "rows": .array([.object(row)])])))
    }
    private let scope = MerchantBusinessScope(realm: "fixture", accountID: 12, epoch: 1)
    @MainActor private final class Reader: MerchantEngagementReading {
        var scope: MerchantBusinessScope? = .init(realm: "fixture", accountID: 12, epoch: 1)
        var authorizationGeneration: UUID? = UUID()
        var isConfigured = true
        var isSyntheticEnabled = true
        var executionAllowed = true
        var deviceAllowed = false
        var accessValue: MerchantEngagementAccess
        var proofCalls = 0, executeCalls = 0
        var failProof = false
        var hold = false
        var waiting: CheckedContinuation<Void, Never>?
        init(_ access: MerchantEngagementAccess) { accessValue = access }
        func canExecute(_ command: MerchantEngagementCommand, merchantID: Int) -> Bool { executionAllowed }
        func permitsDevice(_ action: MerchantEngagementDeviceGrant.Action, merchantID: Int) -> Bool { deviceAllowed }
        func access() async throws -> MerchantEngagementAccess { accessValue }
        func read(_ query: MerchantEngagementQuery) async throws -> MerchantEngagementPayload { throw MerchantBusinessFailure.disabled }
        func proof(_ command: MerchantEngagementCommand) async throws -> MerchantEngagementProof {
            proofCalls += 1
            if hold { await withCheckedContinuation { waiting = $0 } }
            if failProof { throw MerchantBusinessFailure.denied }
            return .init(access: accessValue)
        }
        func execute(_ command: MerchantEngagementCommand, requestID: String, proof: MerchantEngagementProof, scope: MerchantBusinessScope) async throws -> MerchantEngagementReceipt {
            executeCalls += 1; return try .init(command: command, value: .object(["phone": .string("+12025550123")]))
        }
        func resume() { hold = false; waiting?.resume(); waiting = nil }
    }
    @MainActor private final class Delivery: MerchantContactDelivering {
        var calls = 0
        func deliverSynthetic(phone: String, purpose: MerchantContactPurpose) async throws { calls += 1 }
    }
    private func make(current: @escaping () -> Bool = { true }) throws -> (MerchantCustomerContactFlow, Reader) {
        let snap = try snapshot(), selection = try XCTUnwrap(MerchantCustomerContactSelection(scope: scope, authorizationGeneration: nil, snapshot: snap, record: snap.document.rows[0], purpose: .call))
        let reader = try Reader(.init(fields()))
        return (.init(selection: selection, reader: reader, journal: MerchantBusinessMemoryIntentStore(), exports: MerchantExportMemoryRecoveryStore(), current: current), reader)
    }
    func testOpenDoesNotReadOrExecute() throws { let (_, r) = try make(); XCTAssertEqual(r.proofCalls, 0); XCTAssertEqual(r.executeCalls, 0) }
    func testPrepareOnlyCreatesReview() async throws {
        let (f, r) = try make(); await f.prepare(); XCTAssertEqual(f.coordinator.review?.command, f.selection.command); XCTAssertEqual(r.executeCalls, 0)
    }
    func testMissingExecutionGrantCannotDispatch() async throws {
        let (f, r) = try make(); r.executionAllowed = false; await f.prepare(); let review = try XCTUnwrap(f.coordinator.review)
        await f.confirm(review); XCTAssertEqual(r.executeCalls, 0)
    }
    func testDeviceGrantNotInferredFromSyntheticReceipt() async throws {
        let (f, _) = try make(); await f.prepare(); await f.confirm(try XCTUnwrap(f.coordinator.review)); XCTAssertFalse(f.canConsume)
        let d = Delivery(); await f.consume(using: d); XCTAssertEqual(d.calls, 0)
    }
    func testReceiptOneShotWithExplicitFixtureDevicePermission() async throws {
        let (f, r) = try make(); r.deviceAllowed = true; await f.prepare(); await f.confirm(try XCTUnwrap(f.coordinator.review))
        let d = Delivery(); await f.consume(using: d); await f.consume(using: d); XCTAssertEqual(d.calls, 1); XCTAssertTrue(f.consumed)
    }
    func testWrongPurposeAndCustomerRejectedByAdapter() async throws {
        let (f, r) = try make()
        for command in [MerchantEngagementCommand.contact(try .init(61001), .copy), .contact(try .init(61002), .call)] {
            do { _ = try await f.reader.proof(command); XCTFail() } catch {}
        }
        XCTAssertEqual(r.proofCalls, 0)
    }
    func testDifferentMerchantProofRejected() async throws {
        let (f, r) = try make(); r.accessValue = try .init(fields(merchant: 611)); await f.prepare(); XCTAssertNil(f.coordinator.review)
    }
    func testRevokedSensitivePermissionRejected() async throws {
        let (f, r) = try make(); r.accessValue = try .init(fields(sensitive: false)); await f.prepare(); XCTAssertNil(f.coordinator.review)
    }
    func testStaleSourceBeforeOpenDoesNotRead() async throws {
        let (f, r) = try make(current: { false }); await f.prepare(); XCTAssertEqual(r.proofCalls, 0)
    }
    func testFailureThenRetryUsesNewProof() async throws {
        let (f, r) = try make(); r.failProof = true; await f.prepare(); XCTAssertNil(f.coordinator.review)
        r.failProof = false; await f.prepare(); XCTAssertNotNil(f.coordinator.review); XCTAssertEqual(r.proofCalls, 2)
    }
    func testCancelReviewKeepsSelectionButDropsReview() async throws {
        let (f, _) = try make(); await f.prepare(); f.cancelReview(); XCTAssertNil(f.coordinator.review); XCTAssertTrue(f.isCurrent)
    }
    func testCloseInvalidatesPendingProof() async throws {
        let (f, r) = try make(); r.hold = true
        let task = Task { await f.prepare() }; while r.waiting == nil { await Task.yield() }
        f.invalidate(); r.resume(); await task.value; XCTAssertNil(f.coordinator.review); XCTAssertFalse(f.isCurrent)
    }
    func testSourceChangeWhileProofPendingRejected() async throws {
        var current = true; let (f, r) = try make(current: { current }); r.hold = true
        let task = Task { await f.prepare() }; while r.waiting == nil { await Task.yield() }
        current = false; r.resume(); await task.value; XCTAssertNil(f.coordinator.review)
    }
    func testAccountChangeWhileProofPendingRejected() async throws {
        let (f, r) = try make(); r.hold = true
        let task = Task { await f.prepare() }; while r.waiting == nil { await Task.yield() }
        r.scope = .init(realm: "fixture", accountID: 13, epoch: 2); r.resume(); await task.value; XCTAssertNil(f.coordinator.review)
    }
    func testNoUnrelatedDeviceCapability() throws {
        let (f, r) = try make(); r.deviceAllowed = true
        XCTAssertFalse(f.reader.permitsDevice(.saveExport(3), merchantID: 610))
        XCTAssertFalse(f.reader.permitsDevice(.contact(try .init(61001), .copy), merchantID: 610))
        XCTAssertFalse(f.reader.permitsDevice(.contact(try .init(61001), .call), merchantID: 611))
    }
    func testSecondPrepareWhileBusyDoesNotDuplicateProof() async throws {
        let (f, r) = try make(); r.hold = true
        let task = Task { await f.prepare() }; while r.waiting == nil { await Task.yield() }
        await f.prepare(); XCTAssertEqual(r.proofCalls, 1); r.resume(); await task.value
    }
    func testBackgroundInvalidationClearsReceipt() async throws {
        let (f, r) = try make(); r.deviceAllowed = true; await f.prepare(); await f.confirm(try XCTUnwrap(f.coordinator.review))
        f.invalidate(); XCTAssertNil(f.coordinator.receipt); XCTAssertFalse(f.canConsume)
    }
}

import SwiftUI
import UIKit

@MainActor final class MerchantCustomerAppliedQueryTests: XCTestCase {
    @MainActor private final class Source: MerchantBusinessReading {
        var scope: MerchantBusinessScope? = .init(realm: "synthetic-query", accountID: 7, epoch: 1)
        var authorizationGeneration: UUID? = UUID()
        var isConfigured = true
        var isOfflineExample = true
        var canExecuteSyntheticMutation = false
        var reads = 0
        var failure: MerchantBusinessFailure?
        var grant: MerchantBusinessAccess
        init() throws {
            grant = try .init(["active": .bool(true), "merchant": .object(["id": .int(610)]),
                "roleCode": .string("MERCHANT_MANAGER"), "permissions": .array([.string("merchant:crm:read")])])
        }
        func access() async throws -> MerchantBusinessAccess { grant }
        func snapshot(_ query: MerchantBusinessQuery) async throws -> MerchantBusinessSnapshot {
            reads += 1; if let failure { throw failure }
            return try .init(access: grant, document: .init(query: query, payload: .object(["rows": .array([]), "total": .int(0)])))
        }
        func execute(_ mutation: MerchantBusinessMutation, requestID: String, scope: MerchantBusinessScope) async throws -> MerchantBusinessReceipt { throw MerchantBusinessFailure.disabled }
    }
    @MainActor private final class Destination: MerchantEngagementReading {
        var scope: MerchantBusinessScope? = .init(realm: "synthetic-query", accountID: 7, epoch: 1)
        var authorizationGeneration: UUID? = UUID()
        var isConfigured = true
        var isSyntheticEnabled = false
        var calls = 0, writes = 0
        var afterRead: (() -> Void)?
        var grant: MerchantEngagementAccess
        init(merchant: Int = 610) throws {
            grant = try .init(["active": .bool(true), "merchant": .object(["id": .int(merchant)]),
                "roleCode": .string("MERCHANT_MANAGER"), "permissions": .array([.string("merchant:crm:read"), .string("merchant:crm:export")])])
        }
        func access() async throws -> MerchantEngagementAccess { calls += 1; afterRead?(); return grant }
        func read(_ query: MerchantEngagementQuery) async throws -> MerchantEngagementPayload { calls += 1; afterRead?(); return .segments([]) }
        func read(_ query: MerchantEngagementQuery, expectedMerchantID: Int) async throws -> MerchantEngagementPayload {
            guard grant.merchantID == expectedMerchantID else { throw MerchantBusinessFailure.stale }
            return try await read(query)
        }
        func proof(_ command: MerchantEngagementCommand) async throws -> MerchantEngagementProof { calls += 1; afterRead?(); return .init(access: grant) }
        func proof(_ command: MerchantEngagementCommand, expectedMerchantID: Int) async throws -> MerchantEngagementProof {
            guard grant.merchantID == expectedMerchantID else { throw MerchantBusinessFailure.stale }
            return try await proof(command)
        }
        func execute(_ command: MerchantEngagementCommand, requestID: String, proof: MerchantEngagementProof, scope: MerchantBusinessScope) async throws -> MerchantEngagementReceipt { writes += 1; throw MerchantBusinessFailure.disabled }
    }
    private func query() -> MerchantCustomerQuery {
        var result = MerchantCustomerQuery(); result.keyword = " e\u{0301} exact "; result.segment = "repeat"
        result.tagID = 14; result.sourceType = 2; result.sourceStart = "2026-09-01"; result.sourceEnd = "2026-10-01"
        return result
    }
    private func loaded() async throws -> (Source, MerchantBusinessViewModel, MerchantCustomerAppliedQuery) {
        let source = try Source(), model = MerchantBusinessViewModel(reader: source, journal: MerchantBusinessMemoryIntentStore())
        let applied = query(); await model.load(.customers(applied))
        let expected = try XCTUnwrap(model.coordinator.snapshot)
        let selection = try XCTUnwrap(model.customerEngagementSelection(query: .customers(applied), draft: applied, expected: expected, revision: model.revision))
        return (source, model, selection)
    }
    func testAppliedQueryCopiesEveryFieldAndUsesExistingExportPageRules() async throws {
        let (source, _, selection) = try await loaded()
        XCTAssertEqual(selection.filter.customerQuery, query())
        XCTAssertEqual(Array(selection.filter.keyword.utf8), Array(query().keyword.utf8))
        XCTAssertEqual(selection.filter.exportFields["pageNum"], .int(1)); XCTAssertEqual(selection.filter.exportFields["pageSize"], .int(20))
        XCTAssertNil(selection.filter.segmentFields["keyword"]); XCTAssertEqual(source.reads, 1)
    }
    func testUnappliedAndCanonicallyEqualByteChangedQueryCannotOpen() async throws {
        let (_, model, _) = try await loaded(), expected = try XCTUnwrap(model.coordinator.snapshot)
        for key in ["changed", " é exact "] {
            var draft = query(); draft.keyword = key
            XCTAssertNil(model.customerEngagementSelection(query: .customers(query()), draft: draft, expected: expected, revision: model.revision))
        }
    }
    func testAuthorizationChangeBeforeParentObserverRejectsOldSnapshot() async throws {
        let (source, model, _) = try await loaded(), expected = try XCTUnwrap(model.coordinator.snapshot)
        source.authorizationGeneration = UUID()
        XCTAssertNil(model.customerEngagementSelection(query: .customers(query()), draft: query(), expected: expected, revision: model.revision))
        await model.load(.customers(query()))
        XCTAssertNotNil(model.customerEngagementSelection(query: .customers(query()), draft: query(), expected: try XCTUnwrap(model.coordinator.snapshot), revision: model.revision))
    }
    func testOldRenderedRevisionAndFailedReloadCannotCreateRoute() async throws {
        let (source, model, _) = try await loaded(), expected = try XCTUnwrap(model.coordinator.snapshot), old = model.revision
        await model.load(.customers(query()))
        XCTAssertNil(model.customerEngagementSelection(query: .customers(query()), draft: query(), expected: expected, revision: old))
        source.failure = .denied; await model.load(.customers(query()))
        XCTAssertNil(model.customerEngagementSelection(query: .customers(query()), draft: query(), expected: expected, revision: model.revision))
    }
    func testNormalPushParentInvalidationKeepsFrozenChildAliveWithoutDispatch() async throws {
        let (source, model, selection) = try await loaded(), destination = try Destination()
        let child = MerchantCustomerQueryReader(selection: selection, base: destination, source: source, originCurrent: { true })
        model.invalidate()
        XCTAssertTrue(child.isCurrent); XCTAssertEqual(child.selection.filter.customerQuery, query())
        XCTAssertEqual(destination.calls, 0); XCTAssertEqual(destination.writes, 0)
        _ = try await child.access(); XCTAssertEqual(destination.calls, 1); XCTAssertEqual(destination.writes, 0)
    }
    func testRetiredChildAndSameLocationReplacementHaveDifferentIdentity() async throws {
        let (source, model, first) = try await loaded(), destination = try Destination()
        let old = MerchantCustomerQueryReader(selection: first, base: destination, source: source, originCurrent: { true })
        old.retire(); await model.load(.customers(query()))
        let next = try XCTUnwrap(model.customerEngagementSelection(query: .customers(query()), draft: query(), expected: try XCTUnwrap(model.coordinator.snapshot), revision: model.revision))
        let current = MerchantCustomerQueryReader(selection: next, base: destination, source: source, originCurrent: { true })
        XCTAssertNotEqual(first.id, next.id); XCTAssertFalse(old.isCurrent); XCTAssertTrue(current.isCurrent)
        old.retire(); XCTAssertTrue(current.isCurrent)
        do { _ = try await old.access(); XCTFail() } catch { XCTAssertEqual(error as? MerchantBusinessFailure, .stale) }
        XCTAssertEqual(destination.calls, 0)
    }
    func testSourceDestinationAndRootIdentityChangesRetireCapturedChild() async throws {
        for change in 0..<3 {
            let (source, _, selection) = try await loaded(), destination = try Destination(); var root = true
            let child = MerchantCustomerQueryReader(selection: selection, base: destination, source: source, originCurrent: { root })
            if change == 0 { source.scope = .init(realm: "synthetic-query", accountID: 8, epoch: 2) }
            if change == 1 { destination.authorizationGeneration = UUID() }
            if change == 2 { root = false }
            XCTAssertFalse(child.isCurrent); XCTAssertNil(child.scope)
            do { _ = try await child.access(); XCTFail() } catch { XCTAssertEqual(error as? MerchantBusinessFailure, .stale) }
            XCTAssertEqual(destination.calls, 0); XCTAssertEqual(destination.writes, 0)
        }
    }
    func testWrongMerchantFreshAccessAndProofAreRejected() async throws {
        let (source, _, selection) = try await loaded(), destination = try Destination(merchant: 611)
        let child = MerchantCustomerQueryReader(selection: selection, base: destination, source: source, originCurrent: { true })
        do { _ = try await child.access(); XCTFail() } catch { XCTAssertEqual(error as? MerchantBusinessFailure, .stale) }
        do { _ = try await child.proof(.createExport(selection.filter)); XCTFail() } catch { XCTAssertEqual(error as? MerchantBusinessFailure, .stale) }
        XCTAssertEqual(destination.writes, 0)
    }
    func testLateReadDoesNotReturnAfterSourceAuthorizationChanges() async throws {
        let (source, _, selection) = try await loaded(), destination = try Destination()
        let child = MerchantCustomerQueryReader(selection: selection, base: destination, source: source, originCurrent: { true })
        destination.afterRead = { source.authorizationGeneration = UUID() }
        do { _ = try await child.read(.segments); XCTFail() } catch { XCTAssertEqual(error as? MerchantBusinessFailure, .stale) }
        XCTAssertEqual(destination.calls, 1); XCTAssertEqual(destination.writes, 0)
    }
    func testNoNewWriteOrDevicePermissionAndUnticketedPathStaysDisabled() async throws {
        let (source, _, selection) = try await loaded(), destination = try Destination()
        let child = MerchantCustomerQueryReader(selection: selection, base: destination, source: source, originCurrent: { true })
        XCTAssertFalse(child.canExecute(.createExport(selection.filter), merchantID: 610))
        XCTAssertFalse(child.permitsDevice(.saveExport(1), merchantID: 610))
        do { _ = try await child.execute(.createExport(selection.filter), requestID: "unchanged", proof: .init(access: destination.grant), scope: selection.scope); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantBusinessFailure, .disabled) }
        XCTAssertEqual(destination.calls, 0); XCTAssertEqual(destination.writes, 0)
    }
}

extension MerchantCustomerAppliedQueryTests {
    func testOldNavigationBindingCannotReadOrDismissReplacementSession() async throws {
        let (_, _, first) = try await loaded(), (_, _, second) = try await loaded()
        var route: MerchantCustomerAppliedQuery? = first
        let source = Binding<MerchantCustomerAppliedQuery?>(get: { route }, set: { route = $0 })
        let old = source.forMerchantCustomerQuery(first)
        route = second; XCTAssertNil(old.wrappedValue)
        old.wrappedValue = nil; old.wrappedValue = first
        XCTAssertEqual(route?.id, second.id)
        source.forMerchantCustomerQuery(second).wrappedValue = nil; XCTAssertNil(route)
    }
    func testEmptyNavigationBindingNeverAdoptsLaterRoute() async throws {
        var route: MerchantCustomerAppliedQuery? = nil
        let source = Binding<MerchantCustomerAppliedQuery?>(get: { route }, set: { route = $0 })
        let old = source.forMerchantCustomerQuery(nil), (_, _, selection) = try await loaded()
        route = selection; XCTAssertNil(old.wrappedValue); old.wrappedValue = nil
        XCTAssertEqual(route?.id, selection.id)
    }
}

extension MerchantCustomerAppliedQueryTests {
    @MainActor private final class BoundReadTransport: HTTPTransport {
        var merchants: [Int]
        var paths: [String] = []
        init(_ merchants: [Int]) { self.merchants = merchants }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            let path = try XCTUnwrap(request.url?.path); paths.append(path)
            if path == "/api/merchant/access/me" {
                let merchant: Int
                if merchants.count > 1 { merchant = merchants.removeFirst() }
                else { merchant = try XCTUnwrap(merchants.first) }
                return (Data("{\"code\":200,\"data\":{\"active\":true,\"merchant\":{\"id\":\(merchant)},\"roleCode\":\"MERCHANT_MANAGER\",\"permissions\":[\"merchant:crm:read\"]}}".utf8), 200)
            }
            guard path == "/api/merchant/crm/segments" else { throw MerchantBusinessFailure.invalid }
            return (Data(#"{"code":200,"data":[]}"#.utf8), 200)
        }
    }
    @MainActor private final class LegacyReadOnly: MerchantEngagementReading {
        let base: Destination
        init() throws { base = try Destination() }
        var scope: MerchantBusinessScope? { base.scope }
        var isConfigured: Bool { true }
        var isSyntheticEnabled: Bool { false }
        func access() async throws -> MerchantEngagementAccess { try await base.access() }
        func read(_ query: MerchantEngagementQuery) async throws -> MerchantEngagementPayload { try await base.read(query) }
        func proof(_ command: MerchantEngagementCommand) async throws -> MerchantEngagementProof { try await base.proof(command) }
        func execute(_ command: MerchantEngagementCommand, requestID: String, proof: MerchantEngagementProof, scope: MerchantBusinessScope) async throws -> MerchantEngagementReceipt { throw MerchantBusinessFailure.disabled }
    }
    private func actualSessionReader(_ transport: BoundReadTransport) throws -> MerchantEngagementSessionReader {
        let configuration = try APIConfiguration(baseURL: XCTUnwrap(URL(string: "https://bound-reader.example")))
        let service = MerchantEngagementService(configuration: configuration, readTransport: transport)
        let session = try MerchantBusinessSession(accountID: 7, epoch: 1, token: "synthetic-token")
        return MerchantEngagementSessionReader(service: service, session: { session })
    }
    func testSameSessionFreshGrantForOtherMerchantStopsBeforeDocumentRequest() async throws {
        let transport = BoundReadTransport([610, 611]), base = try actualSessionReader(transport), source = try Source()
        source.scope = base.scope
        let model = MerchantBusinessViewModel(reader: source, journal: MerchantBusinessMemoryIntentStore()); await model.load(.customers(query()))
        let selected = try XCTUnwrap(model.customerEngagementSelection(query: .customers(query()), draft: query(), expected: XCTUnwrap(model.coordinator.snapshot), revision: model.revision))
        let child = MerchantCustomerQueryReader(selection: selected, base: base, source: source, originCurrent: { true })
        let scope = base.scope, authorization = base.authorizationGeneration
        let initialGrant = try await child.access()
        XCTAssertEqual(initialGrant.merchantID, 610)
        do { _ = try await child.read(.segments); XCTFail() } catch { XCTAssertEqual(error as? MerchantBusinessFailure, .stale) }
        XCTAssertEqual(base.scope, scope); XCTAssertEqual(base.authorizationGeneration, authorization)
        XCTAssertEqual(transport.paths, ["/api/merchant/access/me", "/api/merchant/access/me"])
        XCTAssertFalse(child.isCurrent); XCTAssertNil(child.scope)
    }
    func testSameCallCorrectMerchantGrantAllowsExactlyOneDocumentRequest() async throws {
        let transport = BoundReadTransport([610]), base = try actualSessionReader(transport)
        let result = try await base.read(.segments, expectedMerchantID: 610)
        guard case .segments(let rows) = result else { return XCTFail("Expected segments") }
        XCTAssertTrue(rows.isEmpty)
        XCTAssertEqual(transport.paths, ["/api/merchant/access/me", "/api/merchant/crm/segments"])
    }
    func testReaderWithoutBoundReadImplementationFailsBeforeUnboundRead() async throws {
        let (source, _, selected) = try await loaded(), base = try LegacyReadOnly()
        let child = MerchantCustomerQueryReader(selection: selected, base: base, source: source, originCurrent: { true })
        do { _ = try await child.read(.segments); XCTFail() } catch { XCTAssertEqual(error as? MerchantBusinessFailure, .disabled) }
        XCTAssertEqual(base.base.calls, 0); XCTAssertEqual(base.base.writes, 0); XCTAssertFalse(child.isCurrent)
    }
}


extension MerchantCustomerAppliedQueryTests {
    func testBoundProofWrongMerchantStopsBeforeSensitiveCustomerRead() async throws {
        let transport = BoundReadTransport([611]), base = try actualSessionReader(transport)
        do {
            _ = try await base.proof(.contact(try MerchantCustomerID(61001), .call), expectedMerchantID: 610)
            XCTFail("A different merchant cannot authorize a selected customer proof")
        } catch { XCTAssertEqual(error as? MerchantBusinessFailure, .stale) }
        XCTAssertEqual(transport.paths, ["/api/merchant/access/me"])
    }
    func testReaderWithoutBoundProofImplementationFailsBeforeUnboundProof() async throws {
        let (source, _, selected) = try await loaded(), base = try LegacyReadOnly()
        let child = MerchantCustomerQueryReader(selection: selected, base: base, source: source, originCurrent: { true })
        do { _ = try await child.proof(.createExport(selected.filter)); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantBusinessFailure, .disabled) }
        XCTAssertEqual(base.base.calls, 0); XCTAssertEqual(base.base.writes, 0)
    }
}


extension MerchantCustomerAppliedQueryTests {
    func testActualQueryOwnerRemovalRetiresOnlyCapturedReader() async throws {
        let (source, _, selected) = try await loaded(), base = try Destination()
        let old = MerchantCustomerQueryReader(selection: selected, base: base, source: source, originCurrent: { true })
        let current = MerchantCustomerQueryReader(selection: selected, base: base, source: source, originCurrent: { true })
        let anchor = MerchantCustomerQueryOwnerAnchor(reader: old)
        MerchantCustomerQueryOwnerAnchor.dismantleUIViewController(UIViewController(), coordinator: anchor.makeCoordinator())
        XCTAssertFalse(old.isCurrent); XCTAssertTrue(current.isCurrent)
        do { _ = try await old.read(.segments); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantBusinessFailure, .stale) }
        XCTAssertEqual(base.calls, 0); XCTAssertEqual(base.writes, 0)
    }
}
