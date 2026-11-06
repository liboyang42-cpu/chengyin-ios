import XCTest
import SwiftUI
import UIKit
@testable import Questify

/// Local history result ownership, using the real namespaced store/session reader.
/// New in-memory test data only; no settlement, Photos, location or HTTP action runs.
@MainActor final class RoamHistoryListOwnerTests: XCTestCase {
    func testNormalReadPreservesRecordOrderSummaryAndDetailSourceWithoutNetwork() throws {
        let r = try ListOwnerRig(), first = try record(2, distance: 2.5, shops: 3), second = try record(1, distance: 1, shops: 0)
        try r.seed([first, second]); var state = RoamHistoryListRead()
        XCTAssertTrue(load(&state, r.reader)); XCTAssertTrue(state.loaded(for: r.reader))
        XCTAssertEqual(state.records(for: r.reader), [first, second]); XCTAssertNil(state.error(for: r.reader))
        let summary = RoamHistorySummary(state.records(for: r.reader))
        XCTAssertEqual(summary.trips, 2); XCTAssertEqual(summary.knownKilometers, 3.5)
        XCTAssertEqual(summary.knownShops, 3)
        XCTAssertEqual(try r.reader.history().first { $0.ts == first.ts }, first)
        XCTAssertEqual(r.wire.calls, 0); XCTAssertEqual(r.storage.writes, 0)
    }

    func testAccountChangeHidesOldRowsAndSummaryBeforeReplacementRead() throws {
        let r = try ListOwnerRig(), old = try record(1, distance: 8, shops: 5), fresh = try record(1, distance: 2, shops: 1)
        try r.seed([old]); var state = RoamHistoryListRead(); XCTAssertTrue(load(&state, r.reader))
        r.session = try ListOwnerRig.session(account: 8); try r.seed([fresh])
        XCTAssertTrue(state.records(for: r.reader).isEmpty); XCTAssertFalse(state.loaded(for: r.reader))
        XCTAssertNil(state.error(for: r.reader)); XCTAssertEqual(RoamHistorySummary(state.records(for: r.reader)).trips, 0)
        XCTAssertTrue(load(&state, r.reader)); XCTAssertEqual(state.records(for: r.reader), [fresh])
        XCTAssertEqual(try r.reader.history().first { $0.ts == old.ts }, fresh)
        XCTAssertEqual(r.wire.calls, 0); XCTAssertEqual(r.storage.writes, 0)
    }

    func testEpochChangeRequiresFreshReadOfSameAccountHistory() throws {
        let r = try ListOwnerRig(), original = try record(1)
        try r.seed([original]); var state = RoamHistoryListRead(); XCTAssertTrue(load(&state, r.reader))
        let keys = r.storage.rows
        r.session = try ListOwnerRig.session(epoch: 2)
        XCTAssertTrue(state.records(for: r.reader).isEmpty); XCTAssertFalse(state.loaded(for: r.reader))
        XCTAssertTrue(load(&state, r.reader)); XCTAssertEqual(state.records(for: r.reader), [original])
        XCTAssertEqual(r.storage.rows, keys); XCTAssertEqual(r.storage.writes, 0)
    }

    func testSameIdentityReaderReplacementCannotBorrowPreviousResultOrFailure() throws {
        let r = try ListOwnerRig(); try r.seed([try record(1)])
        var state = RoamHistoryListRead(); XCTAssertTrue(load(&state, r.reader))
        let replacement = r.makeReader(configured: true)
        XCTAssertEqual(replacement.identity, r.reader.identity)
        XCTAssertTrue(state.records(for: replacement).isEmpty); XCTAssertFalse(state.loaded(for: replacement))
        r.storage.failure = RoamExperienceFailure.historyUnreadable
        XCTAssertFalse(load(&state, r.reader)); XCTAssertNotNil(state.error(for: r.reader))
        XCTAssertNil(state.error(for: replacement))
        r.storage.failure = nil
        XCTAssertTrue(load(&state, replacement)); XCTAssertEqual(state.records(for: replacement).count, 1)
        XCTAssertTrue(state.records(for: r.reader).isEmpty)
    }

    func testMarketDeploymentAndExactNamespaceChangeHidePriorResultImmediately() throws {
        let r = try ListOwnerRig(); try r.seed([try record(1)])
        var state = RoamHistoryListRead(); XCTAssertTrue(load(&state, r.reader))
        for replacement in [try ListOwnerRig.session(market: "us"),
                            try ListOwnerRig.session(deployment: "https://example.test/other"),
                            try ListOwnerRig.session(namespace: "another")] {
            r.session = replacement
            XCTAssertTrue(state.records(for: r.reader).isEmpty); XCTAssertFalse(state.loaded(for: r.reader))
        }
        r.session = try ListOwnerRig.session(namespace: "\u{00E9}"); try r.seed([try record(2)])
        XCTAssertTrue(load(&state, r.reader))
        r.session = try ListOwnerRig.session(namespace: "e\u{0301}")
        XCTAssertTrue(state.records(for: r.reader).isEmpty); XCTAssertFalse(state.loaded(for: r.reader))
        XCTAssertEqual(r.wire.calls, 0)
    }

    func testSignOutImmediatelyHidesOldResultAndKeepsCurrentUnauthorizedErrorSeparate() throws {
        let r = try ListOwnerRig(); try r.seed([try record(1)])
        var state = RoamHistoryListRead(); XCTAssertTrue(load(&state, r.reader))
        r.session = nil
        XCTAssertTrue(state.records(for: r.reader).isEmpty); XCTAssertFalse(state.loaded(for: r.reader))
        XCTAssertNil(state.error(for: r.reader))
        XCTAssertFalse(load(&state, r.reader)); XCTAssertEqual(state.error(for: r.reader) as? APIError, .unauthorized)
        r.session = try ListOwnerRig.session(epoch: 2)
        XCTAssertNil(state.error(for: r.reader)); XCTAssertFalse(state.loaded(for: r.reader))
        XCTAssertTrue(load(&state, r.reader)); XCTAssertEqual(state.records(for: r.reader).count, 1)
    }

    func testReadFailureClearsOldRowsAndExplicitRetryPreservesDurableBytes() throws {
        let r = try ListOwnerRig(); try r.seed([try record(1)])
        var state = RoamHistoryListRead(); XCTAssertTrue(load(&state, r.reader))
        let durable = r.storage.rows
        r.storage.failure = RoamExperienceFailure.historyUnreadable
        XCTAssertFalse(load(&state, r.reader)); XCTAssertFalse(state.loaded(for: r.reader))
        XCTAssertTrue(state.records(for: r.reader).isEmpty)
        XCTAssertEqual(state.error(for: r.reader) as? RoamExperienceFailure, .historyUnreadable)
        r.storage.failure = nil
        XCTAssertTrue(load(&state, r.reader)); XCTAssertNil(state.error(for: r.reader))
        XCTAssertEqual(state.records(for: r.reader).count, 1)
        XCTAssertEqual(r.storage.rows, durable); XCTAssertEqual(r.storage.writes, 0)
    }

    func testOwnerChangesInsideActualLocalReadCannotPublishRowsOrStaleError() throws {
        for fails in [false, true] {
            let r = try ListOwnerRig(); try r.seed([try record(1)])
            var state = RoamHistoryListRead()
            let next = try ListOwnerRig.session(account: 8)
            r.storage.onRead = { r.session = next }
            if fails { r.storage.failure = RoamExperienceFailure.historyUnreadable }
            XCTAssertFalse(load(&state, r.reader)); XCTAssertFalse(state.loaded(for: r.reader))
            XCTAssertTrue(state.records(for: r.reader).isEmpty); XCTAssertNil(state.error(for: r.reader))
            r.storage.onRead = nil; r.storage.failure = nil; try r.seed([try record(2)])
            XCTAssertTrue(load(&state, r.reader)); XCTAssertEqual(state.records(for: r.reader).map(\.ts), [2])
        }
    }

    func testStaleCapturedOwnerDoesNotReadAndCannotAuthorizeEmptyLiveEntry() throws {
        let r = try ListOwnerRig(); var state = RoamHistoryListRead(), entry = RoamHistoryLiveEntry()
        entry.appear(); let original = entry.beginRead(reader: r.reader)
        r.session = try ListOwnerRig.session(epoch: 2)
        XCTAssertFalse(state.load(reader: r.reader, expected: original))
        XCTAssertEqual(r.storage.readKeys.count, 0); XCTAssertFalse(state.loaded(for: r.reader))
        XCTAssertFalse(entry.canOpen(reader: r.reader, hasDestination: true))
        let current = entry.beginRead(reader: r.reader)
        XCTAssertTrue(state.load(reader: r.reader, expected: current))
        entry.acceptRead(isEmpty: state.records(for: r.reader).isEmpty, snapshot: current, reader: r.reader)
        XCTAssertTrue(entry.canOpen(reader: r.reader, hasDestination: true))
        XCTAssertEqual(r.wire.calls, 0)
    }

    func testLocalHistoryWithoutRemoteServiceRemainsReadable() throws {
        // isConfigured describes the remote service. The actual history reader
        // intentionally allows a current account to read its own local store.
        let r = try ListOwnerRig(); try r.seed([try record(1)])
        let localOnly = r.makeReader(configured: false); var state = RoamHistoryListRead()
        XCTAssertFalse(localOnly.isConfigured)
        XCTAssertTrue(load(&state, localOnly)); XCTAssertTrue(state.loaded(for: localOnly))
        XCTAssertEqual(state.records(for: localOnly).count, 1); XCTAssertNil(state.error(for: localOnly))
        XCTAssertEqual(r.wire.calls, 0); XCTAssertEqual(r.storage.writes, 0)
    }

    func testActualHistoryHostReloadsReplacementReaderWithoutNetworkOrWrites() async throws {
        let first = try ListOwnerRig(), second = try ListOwnerRig(account: 8)
        try first.seed([try record(1)]); try second.seed([try record(2)])
        let host = UIHostingController(rootView: RoamHistoryView(reader: first.reader))
        let window = UIWindow(frame: UIScreen.main.bounds); window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.loadViewIfNeeded(); host.view.layoutIfNeeded()
        try await waitFor { !first.storage.readKeys.isEmpty }
        host.rootView = RoamHistoryView(reader: second.reader)
        host.view.layoutIfNeeded()
        try await waitFor { !second.storage.readKeys.isEmpty }
        XCTAssertTrue(first.storage.readKeys.allSatisfy { $0 == first.session?.identity.scope.storageKey })
        XCTAssertTrue(second.storage.readKeys.allSatisfy { $0 == second.session?.identity.scope.storageKey })
        XCTAssertEqual(first.wire.calls + second.wire.calls, 0)
        XCTAssertEqual(first.storage.writes + second.storage.writes, 0)
    }

    private func record(_ timestamp: Int64, distance: Double = 1, shops: Int = 1) throws -> RoamHistoryRecord {
        try JSONDecoder().decode(RoamHistoryRecord.self, from: JSONSerialization.data(withJSONObject:
            ["ts": timestamp, "distance": distance, "shops": shops, "zone": "synthetic recorded route"]))
    }
    private func load(_ state: inout RoamHistoryListRead, _ reader: any RoamExperienceReading) -> Bool {
        state.load(reader: reader, expected: RoamHistoryLiveOwner(reader: reader))
    }
    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("The hosted local history read did not occur"); throw APIError.notConfigured
    }
}

@MainActor private final class ListOwnerRig {
    var session: RoamExperienceSession?
    let storage = ListOwnerStorage()
    let wire = ListOwnerNoHTTP()
    private(set) var store: RoamHistoryStore!
    private(set) var reader: RoamExperienceSessionReader!
    init(account: Int = 7) throws {
        session = try Self.session(account: account)
        store = RoamHistoryStore(storage: storage, currentScope: { [weak self] in self?.session?.identity.scope })
        reader = makeReader(configured: true)
    }
    static func session(account: Int = 7, epoch: UInt64 = 1, market: String = "cn",
                        deployment: String = "https://example.test/roam", namespace: String = "history-list-tests") throws -> RoamExperienceSession {
        try .init(scope: .init(market: market, deployment: XCTUnwrap(URL(string: deployment)), accountID: account,
            namespace: namespace), epoch: epoch, token: "synthetic-token")
    }
    func makeReader(configured: Bool) -> RoamExperienceSessionReader {
        let service = configured ? try? RoamExperienceService(configuration: .init(baseURL: XCTUnwrap(URL(string: "https://example.test/roam"))), transport: wire) : nil
        return .init(service: service, store: store, currentSession: { [weak self] in self?.session })
    }
    func seed(_ records: [RoamHistoryRecord]) throws {
        struct Seed: Encodable { let version = 1; let scope: RoamHistoryScope; let records: [RoamHistoryRecord] }
        let scope = try XCTUnwrap(session?.identity.scope)
        // New test-only local envelope, not a settlement writer or production seed.
        storage.rows[scope.storageKey] = try JSONEncoder().encode(Seed(scope: scope, records: records))
    }
}
@MainActor private final class ListOwnerStorage: RoamHistoryDataStoring {
    var rows: [String: Data] = [:], readKeys: [String] = []
    var writes = 0
    var failure: Error?
    var onRead: (() -> Void)?
    func read(key: String) throws -> Data? {
        readKeys.append(key); onRead?()
        if let failure { throw failure }
        return rows[key]
    }
    func write(_ data: Data, key: String) throws { writes += 1; rows[key] = data }
}
@MainActor private final class ListOwnerNoHTTP: HTTPTransport {
    var calls = 0
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        calls += 1; throw APIError.notConfigured
    }
}
