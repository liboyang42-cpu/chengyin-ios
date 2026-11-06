import XCTest
import SwiftUI
import UIKit
@testable import Questify

/// Real local history and the actual medal representable's final controller boundary.
/// Tests call that boundary only after invalidation, so no activity controller is made
/// or presented. No test calls Photos, HTTP, or an external sharing destination.
@MainActor final class RoamMedalSystemShareSourceTests: XCTestCase {
    func testBothEarnedMedalKindsKeepExactPreparedImageAndNoRouteSelection() throws {
        let r = try MedalExportRig(), record = try record()
        try r.seed([record]); let durable = r.storage.rows
        for kind in RoamMedalShareSelection.Kind.allCases {
            let selection = try XCTUnwrap(RoamMedalShareSelection(record: record, kind: kind))
            let image = try XCTUnwrap(RoamMedalShareRenderer.render(selection.card))
            let request = try request(selection, r, image: image)
            XCTAssertTrue(request.image === image)
            XCTAssertEqual(request.selection.record, record); XCTAssertFalse(request.selection.includeRoute)
            XCTAssertTrue(request.isCurrent(reader: r.reader))
            XCTAssertEqual(image.cgImage?.width, 750); XCTAssertEqual(image.cgImage?.height, 1000)
        }
        XCTAssertEqual(r.storage.rows, durable); XCTAssertEqual(r.storage.writes, 0); XCTAssertEqual(r.wire.calls, 0)
    }

    func testChangedEarnedNameOrOtherRecordFieldAfterSheetBodyCannotCreateMedalController() throws {
        let r = try MedalExportRig(), original = try record()
        let changes: [[String: Any]] = [["medal": "Replacement journey medal"],
                                       ["shopMedalName": "Replacement shop medal"],
                                       ["distance": 9.0], ["zone": "Another recorded route"]]
        for change in changes {
            for kind in RoamMedalShareSelection.Kind.allCases {
                try r.seed([original])
                let selected = try XCTUnwrap(RoamMedalShareSelection(record: original, kind: kind))
                let accepted = try request(selected, r)
                XCTAssertTrue(accepted.isCurrent(reader: r.reader)) // Previously accepted sheet body.
                let surface = RoamMedalSystemShare(request: accepted, reader: r.reader)
                try r.seed([try record(change)])
                assertNotActivity(surface.makeController())
            }
        }
        XCTAssertEqual(r.storage.writes, 0); XCTAssertEqual(r.wire.calls, 0)
    }

    func testRemovedRecordAfterSheetBodyDoesNotPassCachedImageToUIKit() throws {
        let r = try MedalExportRig(), original = try record()
        try r.seed([original]); let selected = try XCTUnwrap(RoamMedalShareSelection(record: original, kind: .journey))
        let accepted = try request(selected, r)
        let surface = RoamMedalSystemShare(request: accepted, reader: r.reader)
        try r.seed([])
        assertNotActivity(surface.makeController())
        XCTAssertEqual(r.storage.writes, 0); XCTAssertEqual(r.wire.calls, 0)
    }

    func testOwnerEpochNamespaceAndReaderReplacementFailAtActualMedalCreationBoundary() throws {
        let original = try record()
        let replacements = [try MedalExportRig.session(account: 8), try MedalExportRig.session(epoch: 2),
                            try MedalExportRig.session(namespace: "changed"), try MedalExportRig.session(market: "us")]
        for replacement in replacements {
            let r = try MedalExportRig(); try r.seed([original])
            let selected = try XCTUnwrap(RoamMedalShareSelection(record: original, kind: .shop))
            let accepted = try request(selected, r)
            r.session = replacement; try r.seed([original])
            let reads = r.storage.readKeys.count
            assertNotActivity(RoamMedalSystemShare(request: accepted, reader: r.reader).makeController())
            XCTAssertEqual(r.storage.readKeys.count, reads, "A new owner store cannot authorize the old card")
        }
        let r = try MedalExportRig(); try r.seed([original])
        let selected = try XCTUnwrap(RoamMedalShareSelection(record: original, kind: .journey))
        let accepted = try request(selected, r), replacement = r.makeReader(configured: true)
        XCTAssertEqual(replacement.identity, r.reader.identity)
        assertNotActivity(RoamMedalSystemShare(request: accepted, reader: replacement).makeController())
        r.session = nil
        assertNotActivity(RoamMedalSystemShare(request: accepted, reader: r.reader).makeController())
        XCTAssertEqual(r.storage.writes, 0); XCTAssertEqual(r.wire.calls, 0)
    }

    func testOwnerChangeDuringLastLocalReadRejectsMedalControllerWithoutReadingNewOwner() throws {
        let r = try MedalExportRig(), original = try record()
        try r.seed([original]); let selected = try XCTUnwrap(RoamMedalShareSelection(record: original, kind: .journey))
        let accepted = try request(selected, r), next = try MedalExportRig.session(epoch: 2)
        let reads = r.storage.readKeys.count
        r.storage.onRead = { r.session = next }
        assertNotActivity(RoamMedalSystemShare(request: accepted, reader: r.reader).makeController())
        XCTAssertEqual(r.storage.readKeys.count, reads + 1)
        XCTAssertEqual(r.storage.writes, 0); XCTAssertEqual(r.wire.calls, 0)
    }

    func testUnreadableCorruptOrAmbiguousHistoryCreatesNoActivityAndDoesNotRepairStore() throws {
        let r = try MedalExportRig(), original = try record()
        try r.seed([original]); let selected = try XCTUnwrap(RoamMedalShareSelection(record: original, kind: .journey))
        let accepted = try request(selected, r), surface = RoamMedalSystemShare(request: accepted, reader: r.reader)
        let durable = r.storage.rows
        r.storage.failure = RoamExperienceFailure.historyUnreadable
        assertNotActivity(surface.makeController()); XCTAssertEqual(r.storage.rows, durable)
        r.storage.failure = nil
        let key = try XCTUnwrap(r.session?.identity.scope.storageKey)
        r.storage.rows[key] = Data("not an envelope".utf8)
        assertNotActivity(surface.makeController())
        XCTAssertEqual(r.storage.rows[key], Data("not an envelope".utf8))
        try r.seed([original, original]); assertNotActivity(surface.makeController())
        XCTAssertEqual(r.storage.writes, 0); XCTAssertEqual(r.wire.calls, 0)
    }

    func testLocalReadRecoveryKeepsOriginalGateAndAllowsOnlyFreshExplicitRequest() throws {
        let r = try MedalExportRig(), original = try record()
        try r.seed([original]); let selected = try XCTUnwrap(RoamMedalShareSelection(record: original, kind: .shop))
        let first = try request(selected, r)
        r.storage.failure = RoamExperienceFailure.historyUnreadable
        assertNotActivity(RoamMedalSystemShare(request: first, reader: r.reader).makeController())
        r.storage.failure = nil
        try r.seed([try record(["ts": 1700000000001 as Int64]), original])
        let fresh = try request(selected, r)
        XCTAssertNotEqual(first.id, fresh.id); XCTAssertTrue(fresh.isCurrent(reader: r.reader))
        let localOnly = r.makeReader(configured: false)
        XCTAssertEqual(try localOnly.history().count, 2)
        XCTAssertNil(RoamMedalShareAuthority(selection: selected, reader: localOnly))
        XCTAssertNil(RoamHistorySystemShareRequest(image: UIImage(), selection: .init(record: original, includeRoute: false),
            owner: .init(reader: localOnly), reader: localOnly))
        XCTAssertEqual(r.storage.writes, 0); XCTAssertEqual(r.wire.calls, 0)
    }

    func testActualMedalViewPrepareThenChangedSourceRefusesOriginalSystemButtonBeforePresentation() async throws {
        let r = try MedalExportRig(), original = try record()
        try r.seed([original]); let selected = try XCTUnwrap(RoamMedalShareSelection(record: original, kind: .journey))
        let host = UIHostingController(rootView: NavigationStack { RoamMedalShareView(selection: selected, reader: r.reader) })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 1100))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.loadViewIfNeeded(); host.view.layoutIfNeeded()
        try await tap("roam.medalShare.prepare", in: window)
        try await waitFor("Prepared image appears") { self.find("roam.medalShare.preview", in: window) != nil }
        try r.seed([])
        try await tap("roam.medalShare.system", in: window)
        try await waitFor("The actual source guard rejects before UIKit presentation") {
            self.find("roam.medalShare.sourceChanged", in: window) != nil
        }
        XCTAssertNil(find("roam.medalShare.preview", in: window))
        XCTAssertNil(host.presentedViewController)
        XCTAssertEqual(r.storage.writes, 0); XCTAssertEqual(r.wire.calls, 0)
    }

    private func request(_ selection: RoamMedalShareSelection, _ r: MedalExportRig,
                         image: UIImage = UIImage()) throws -> RoamHistorySystemShareRequest {
        let authority = try XCTUnwrap(RoamMedalShareAuthority(selection: selection, reader: r.reader))
        XCTAssertTrue(authority.isCurrent(r.reader))
        return try XCTUnwrap(RoamHistorySystemShareRequest(image: image,
            selection: .init(record: selection.record, includeRoute: false), owner: .init(reader: r.reader), reader: r.reader))
    }
    private func record(_ extra: [String: Any] = [:]) throws -> RoamHistoryRecord {
        let fields: [String: Any] = ["ts": 1700000000000 as Int64, "zone": "Synthetic route", "distance": 1.0,
                                    "medal": "Earned journey medal", "shopMedalName": "Earned shop medal"]
        return try JSONDecoder().decode(RoamHistoryRecord.self, from:
            JSONSerialization.data(withJSONObject: fields.merging(extra) { _, new in new }))
    }
    private func assertNotActivity(_ controller: UIViewController, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(controller is UIActivityViewController, file: file, line: line)
        XCTAssertNil(controller.presentedViewController, file: file, line: line)
    }
    private func waitFor(_ message: String, _ condition: () -> Bool) async throws {
        for _ in 0..<150 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail(message); throw APIError.notConfigured
    }
    private func tap(_ id: String, in window: UIWindow) async throws {
        try await waitFor("Original control exists: \(id)") { self.find(id, in: window) != nil }
        let control = try XCTUnwrap(find(id, in: window))
        if let control = control as? UIControl { control.sendActions(for: .touchUpInside) }
        else { XCTAssertTrue(control.accessibilityActivate(), "Original medal control must activate") }
    }
    private func find(_ id: String, in window: UIWindow) -> NSObject? {
        var seen = Set<ObjectIdentifier>()
        func visit(_ root: NSObject) -> NSObject? {
            guard seen.insert(ObjectIdentifier(root)).inserted else { return nil }
            if (root as? UIAccessibilityIdentification)?.accessibilityIdentifier == id { return root }
            if let view = root as? UIView {
                for child in view.subviews { if let found = visit(child) { return found } }
            }
            if let children = root.accessibilityElements {
                for child in children { if let child = child as? NSObject, let found = visit(child) { return found } }
            }
            let count = root.accessibilityElementCount()
            if count > 0 && count < 1000 {
                for i in 0..<count {
                    if let child = root.accessibilityElement(at: i) as? NSObject, let found = visit(child) { return found }
                }
            }
            return nil
        }
        return visit(window)
    }
}

@MainActor private final class MedalExportRig {
    var session: RoamExperienceSession?
    let storage = MedalExportStorage()
    let wire = MedalExportNoHTTP()
    private(set) var store: RoamHistoryStore!
    private(set) var reader: RoamExperienceSessionReader!
    init() throws {
        session = try Self.session()
        store = RoamHistoryStore(storage: storage, currentScope: { [weak self] in self?.session?.identity.scope })
        reader = makeReader(configured: true)
    }
    static func session(account: Int = 7, epoch: UInt64 = 1, market: String = "cn",
                        deployment: String = "https://example.test/roam", namespace: String = "medal-export-tests") throws -> RoamExperienceSession {
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
@MainActor private final class MedalExportStorage: RoamHistoryDataStoring {
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
@MainActor private final class MedalExportNoHTTP: HTTPTransport {
    var calls = 0
    func send(_ request: URLRequest) async throws -> (Data, Int) { calls += 1; throw APIError.notConfigured }
}
