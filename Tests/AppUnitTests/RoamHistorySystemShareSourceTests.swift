import XCTest
import SwiftUI
import UIKit
@testable import Questify

/// Actual local store/session-reader checks for the system-export request. No test
/// opens an activity controller, accesses Photos, contacts HTTP or settles a walk.
@MainActor final class RoamHistorySystemShareSourceTests: XCTestCase {
    func testCurrentFullRecordRetainsExactPreparedImageAndRouteChoice() throws {
        let r = try SystemShareSourceRig(), record = try record(), image = UIImage()
        try r.seed([record]); let bytes = r.storage.rows
        for includeRoute in [false, true] {
            let selection = RoamSharePhotoSaveState.Selection(record: record, includeRoute: includeRoute)
            let request = try XCTUnwrap(RoamHistorySystemShareRequest(image: image, selection: selection,
                owner: .init(reader: r.reader), reader: r.reader))
            XCTAssertTrue(request.image === image); XCTAssertEqual(request.selection, selection)
            XCTAssertTrue(request.isCurrent(reader: r.reader))
        }
        XCTAssertEqual(r.storage.rows, bytes); XCTAssertEqual(r.storage.writes, 0)
        XCTAssertEqual(r.wire.calls, 0)
    }

    func testRemovedRecordCannotStartSystemExportFromCachedImage() throws {
        let r = try SystemShareSourceRig(), original = try record()
        try r.seed([original]); let captured = RoamHistoryLiveOwner(reader: r.reader)
        try r.seed([]) // Same owner, but the locally retained history no longer has this card.
        XCTAssertNil(request(original, r, owner: captured)); XCTAssertEqual(r.storage.writes, 0)
        XCTAssertEqual(r.wire.calls, 0)
    }

    func testSameTimestampDoesNotAuthorizeAnyChangedRecordField() throws {
        let r = try SystemShareSourceRig(), original = try record()
        let changedFields: [[String: Any]] = [
            ["serverSessionID": 41], ["zone": "Changed zone"], ["date": "Changed date"],
            ["dateLine": "Changed date line"], ["distance": 2.5], ["explorePct": 30],
            ["shops": 3], ["time": "11:22"], ["durSec": 682],
            ["photos": ["synthetic-photo-ref"]],
            ["pois": [["id": 1, "name": "Changed place", "lat": 31.2, "lng": 121.4]]],
            ["track": [["lat": 31.2, "lng": 121.4]]],
            ["medal": "Changed earned medal"], ["shopMedalName": "Changed earned shop medal"]
        ]
        for fields in changedFields {
            let changed = try record(fields)
            XCTAssertEqual(changed.ts, original.ts); XCTAssertNotEqual(changed, original)
            try r.seed([changed]); XCTAssertNil(request(original, r), "Changed field: \(fields.keys)")
        }
        XCTAssertEqual(r.storage.writes, 0); XCTAssertEqual(r.wire.calls, 0)
    }

    func testCurrentRecordIsRecheckedAgainBeforePresentation() throws {
        let r = try SystemShareSourceRig(), original = try record()
        try r.seed([original]); let accepted = try XCTUnwrap(request(original, r))
        try r.seed([try record(["distance": 9])])
        XCTAssertFalse(accepted.isCurrent(reader: r.reader))
        try r.seed([]); XCTAssertFalse(accepted.isCurrent(reader: r.reader))
        XCTAssertEqual(r.storage.writes, 0); XCTAssertEqual(r.wire.calls, 0)
    }

    func testSourceLostAfterSheetBodyCannotCreateAnActivityController() throws {
        let r = try SystemShareSourceRig(), original = try record()
        try r.seed([original]); let accepted = try XCTUnwrap(request(original, r))
        XCTAssertTrue(accepted.isCurrent(reader: r.reader)) // The sheet body previously accepted it.
        try r.seed([])
        XCTAssertNil(accepted.makeActivityController(reader: r.reader))
        // Only the rejected branch runs: no activity controller is made or presented.
        XCTAssertEqual(r.storage.writes, 0); XCTAssertEqual(r.wire.calls, 0)
    }

    func testUnrelatedNewHistoryDoesNotInvalidateExistingExactRecord() throws {
        let r = try SystemShareSourceRig(), original = try record()
        try r.seed([original]); let accepted = try XCTUnwrap(request(original, r))
        try r.seed([try record(["ts": 1700000000001]), original])
        XCTAssertTrue(accepted.isCurrent(reader: r.reader))
        XCTAssertNotNil(request(original, r)); XCTAssertEqual(r.storage.writes, 0)
    }

    func testAccountEpochMarketDeploymentNamespaceAndLogoutCannotReuseRequest() throws {
        let r = try SystemShareSourceRig(), original = try record()
        try r.seed([original]); let owner = RoamHistoryLiveOwner(reader: r.reader)
        let accepted = try XCTUnwrap(request(original, r, owner: owner))
        let replacements = [try SystemShareSourceRig.session(account: 8),
                            try SystemShareSourceRig.session(epoch: 2),
                            try SystemShareSourceRig.session(market: "us"),
                            try SystemShareSourceRig.session(deployment: "https://example.test/other"),
                            try SystemShareSourceRig.session(namespace: "another")]
        for replacement in replacements {
            r.session = replacement; try r.seed([original])
            let reads = r.storage.readKeys.count
            XCTAssertFalse(accepted.isCurrent(reader: r.reader)); XCTAssertNil(request(original, r, owner: owner))
            XCTAssertEqual(r.storage.readKeys.count, reads, "A mismatched owner must not read a replacement store")
        }
        r.session = nil
        XCTAssertFalse(accepted.isCurrent(reader: r.reader)); XCTAssertNil(request(original, r, owner: owner))
        XCTAssertEqual(r.storage.writes, 0); XCTAssertEqual(r.wire.calls, 0)
    }

    func testExactNamespaceBytesAndReplacementReaderCannotBorrowAnExport() throws {
        let r = try SystemShareSourceRig(), original = try record()
        r.session = try SystemShareSourceRig.session(namespace: "\u{00E9}"); try r.seed([original])
        let accepted = try XCTUnwrap(request(original, r))
        let replacement = r.makeReader(configured: true)
        XCTAssertEqual(replacement.identity, r.reader.identity)
        XCTAssertFalse(accepted.isCurrent(reader: replacement))
        r.session = try SystemShareSourceRig.session(namespace: "e\u{0301}"); try r.seed([original])
        XCTAssertFalse(accepted.isCurrent(reader: r.reader)); XCTAssertEqual(r.wire.calls, 0)
    }

    func testOwnerChangeInsideActualStoreReadCannotCreateOrPresentOldRequest() throws {
        let r = try SystemShareSourceRig(), original = try record()
        try r.seed([original]); let accepted = try XCTUnwrap(request(original, r))
        let next = try SystemShareSourceRig.session(epoch: 2)
        r.storage.onRead = { r.session = next }
        XCTAssertNil(request(original, r)); XCTAssertFalse(accepted.isCurrent(reader: r.reader))
        r.storage.onRead = nil
        let fresh = try XCTUnwrap(request(original, r))
        let third = try SystemShareSourceRig.session(epoch: 3)
        r.storage.onRead = { r.session = third }
        XCTAssertFalse(fresh.isCurrent(reader: r.reader))
        XCTAssertEqual(r.storage.writes, 0); XCTAssertEqual(r.wire.calls, 0)
    }

    func testLockedOrCorruptStoreRejectsExportWithoutRepairOrWrite() throws {
        let r = try SystemShareSourceRig(), original = try record()
        try r.seed([original]); let accepted = try XCTUnwrap(request(original, r))
        let durable = r.storage.rows
        r.storage.failure = RoamExperienceFailure.historyUnreadable
        XCTAssertNil(request(original, r)); XCTAssertFalse(accepted.isCurrent(reader: r.reader))
        XCTAssertEqual(r.storage.rows, durable)
        r.storage.failure = nil
        let key = try XCTUnwrap(r.session?.identity.scope.storageKey)
        r.storage.rows[key] = Data("not a history envelope".utf8)
        XCTAssertNil(request(original, r)); XCTAssertFalse(accepted.isCurrent(reader: r.reader))
        XCTAssertEqual(r.storage.rows[key], Data("not a history envelope".utf8))
        XCTAssertEqual(r.storage.writes, 0); XCTAssertEqual(r.wire.calls, 0)
    }

    func testDuplicateTimestampEnvelopeCannotSupplyAnAmbiguousShareRecord() throws {
        let r = try SystemShareSourceRig(), original = try record()
        try r.seed([original]); let accepted = try XCTUnwrap(request(original, r))
        try r.seed([original, original])
        XCTAssertNil(request(original, r)); XCTAssertFalse(accepted.isCurrent(reader: r.reader))
        XCTAssertEqual(r.storage.writes, 0); XCTAssertEqual(r.wire.calls, 0)
    }

    func testUnconfiguredShareGateRemainsClosedEvenWhenLocalHistoryCanBeRead() throws {
        let r = try SystemShareSourceRig(), original = try record()
        try r.seed([original]); let localOnly = r.makeReader(configured: false)
        XCTAssertEqual(try localOnly.history(), [original])
        XCTAssertNil(RoamHistorySystemShareRequest(image: UIImage(), selection: .init(record: original, includeRoute: false),
            owner: .init(reader: localOnly), reader: localOnly))
        XCTAssertEqual(r.storage.writes, 0); XCTAssertEqual(r.wire.calls, 0)
    }

    func testExplicitRetryAfterReadRecoveryCreatesANewRequestWithoutWrites() throws {
        let r = try SystemShareSourceRig(), original = try record(), image = UIImage()
        try r.seed([original]); let owner = RoamHistoryLiveOwner(reader: r.reader)
        let selection = RoamSharePhotoSaveState.Selection(record: original, includeRoute: false)
        let first = try XCTUnwrap(RoamHistorySystemShareRequest(image: image, selection: selection, owner: owner, reader: r.reader))
        r.storage.failure = RoamExperienceFailure.historyUnreadable
        XCTAssertNil(RoamHistorySystemShareRequest(image: image, selection: selection, owner: owner, reader: r.reader))
        r.storage.failure = nil
        let retry = try XCTUnwrap(RoamHistorySystemShareRequest(image: image, selection: selection, owner: owner, reader: r.reader))
        XCTAssertNotEqual(first.id, retry.id); XCTAssertTrue(retry.image === image)
        XCTAssertEqual(r.storage.writes, 0); XCTAssertEqual(r.wire.calls, 0)
    }

    func testActualShareViewMountDoesNotExportSaveOrFetchAnything() throws {
        let r = try SystemShareSourceRig(), original = try record()
        try r.seed([original]); let durable = r.storage.rows
        let host = UIHostingController(rootView: NavigationStack { RoamHistoryShareView(record: original, reader: r.reader) })
        host.loadViewIfNeeded(); host.view.layoutIfNeeded()
        XCTAssertNotNil(host.view); XCTAssertEqual(r.storage.rows, durable)
        XCTAssertEqual(r.storage.writes, 0); XCTAssertEqual(r.wire.calls, 0)
        XCTAssertTrue(r.storage.readKeys.isEmpty, "Preparing and exporting remain explicit actions")
    }

    private func record(_ extra: [String: Any] = [:]) throws -> RoamHistoryRecord {
        let fields: [String: Any] = ["ts": 1700000000000 as Int64, "zone": "Synthetic route", "distance": 1.0,
                                    "shops": 1, "medal": "Earned journey medal"]
        return try JSONDecoder().decode(RoamHistoryRecord.self, from:
            JSONSerialization.data(withJSONObject: fields.merging(extra) { _, new in new }))
    }
    private func request(_ record: RoamHistoryRecord, _ r: SystemShareSourceRig,
                         owner: RoamHistoryLiveOwner? = nil) -> RoamHistorySystemShareRequest? {
        .init(image: UIImage(), selection: .init(record: record, includeRoute: false),
              owner: owner ?? .init(reader: r.reader), reader: r.reader)
    }
}

@MainActor private final class SystemShareSourceRig {
    var session: RoamExperienceSession?
    let storage = SystemShareSourceStorage()
    let wire = SystemShareNoHTTP()
    private(set) var store: RoamHistoryStore!
    private(set) var reader: RoamExperienceSessionReader!
    init() throws {
        session = try Self.session()
        store = RoamHistoryStore(storage: storage, currentScope: { [weak self] in self?.session?.identity.scope })
        reader = makeReader(configured: true)
    }
    static func session(account: Int = 7, epoch: UInt64 = 1, market: String = "cn",
                        deployment: String = "https://example.test/roam", namespace: String = "system-share-tests") throws -> RoamExperienceSession {
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
        storage.rows[scope.storageKey] = try JSONEncoder().encode(Seed(scope: scope, records: records))
    }
}
@MainActor private final class SystemShareSourceStorage: RoamHistoryDataStoring {
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
@MainActor private final class SystemShareNoHTTP: HTTPTransport {
    var calls = 0
    func send(_ request: URLRequest) async throws -> (Data, Int) { calls += 1; throw APIError.notConfigured }
}
