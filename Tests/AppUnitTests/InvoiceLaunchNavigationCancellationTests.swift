import XCTest
import Foundation
@testable import Questify

@MainActor final class InvoiceLaunchNavigationCancellationTests: XCTestCase {
    func testCancelledOverviewDoesNotRetireQueuedDetail() async throws {
        let h = try Harness(), revision = h.model.identityRevision
        let overview = Task { await h.model.refresh() }; await h.wire.waitForPending()
        var began = false
        let b = Task { began = true; await h.model.loadDetail(52) }; await waitUntil { began }
        overview.cancel(); h.wire.resume()
        await overview.value; await b.value
        XCTAssertEqual(h.wire.paths, ["titles", "detail"])
        XCTAssertEqual(h.model.detail?.id, 52)
        XCTAssertEqual(h.model.identityRevision, revision)
        XCTAssertNil(h.model.issue); XCTAssertEqual(h.wire.maxActive, 1)
        XCTAssertFalse(h.model.allows(.apply)); XCTAssertTrue(h.memory.values.isEmpty)
    }
    func testCancellationCannotHideActualIdentityLoss() async throws {
        let h = try Harness(), revision = h.model.identityRevision
        let overview = Task { await h.model.refresh() }; await h.wire.waitForPending()
        var began = false
        let b = Task { began = true; await h.model.loadDetail(52) }; await waitUntil { began }
        h.current = nil; overview.cancel(); h.wire.resume()
        await overview.value; await b.value
        XCTAssertNotEqual(h.model.identityRevision, revision)
        XCTAssertEqual(h.wire.paths, ["titles"])
        XCTAssertNil(h.model.detail); XCTAssertEqual(h.model.issue, "session")
        XCTAssertFalse(h.model.busy); XCTAssertFalse(h.model.allows(.apply))
    }
    func testCancelledDetailDoesNotPublishItsResultOrInventSessionFailure() async throws {
        let h = try Harness(), revision = h.model.identityRevision
        let a = Task { await h.model.loadDetail(51) }; await h.wire.waitForPending()
        a.cancel(); h.wire.resume(); await a.value
        XCTAssertNil(h.model.detail); XCTAssertNil(h.model.issue)
        XCTAssertEqual(h.model.identityRevision, revision); XCTAssertFalse(h.model.busy)
        await h.model.loadDetail(52)
        XCTAssertEqual(h.model.detail?.id, 52); XCTAssertEqual(h.wire.ids, [51, 52])
        XCTAssertEqual(h.wire.maxActive, 1)
    }
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<500 { if condition() { return }; await Task.yield() }
        XCTFail("Synthetic navigation did not start")
    }
    @MainActor private final class Memory: InvoiceLaunchStorage {
        var values: [String: Data] = [:]
        func read(_ key: String) throws -> Data? { values[key] }
        func write(_ data: Data, key: String) throws { values[key] = data }
        func remove(_ key: String) throws { values.removeValue(forKey: key) }
    }
    @MainActor private final class Harness {
        let captured: InvoiceLaunchSession
        var current: InvoiceLaunchSession?
        let wire = Wire(), memory = Memory()
        lazy var service = InvoiceLaunchService(session: captured, transport: wire,
            enabled: { true }, current: { [unowned self] in current })
        lazy var store = InvoiceLaunchPendingStore(session: captured, storage: memory)
        lazy var model = InvoiceLaunchPresentation(coordinator: try! InvoiceLaunchCoordinator(service: service, store: store),
            isCurrent: { [unowned self] in current == captured })
        init() throws {
            captured = try InvoiceLaunchSession(baseURL: URL(string: "https://example.test/native")!,
                namespace: "synthetic-navigation", accountID: 7, role: "player", epoch: 1, token: "synthetic-token")
            current = captured
        }
    }
    // Same CheckedContinuation suspension pattern as existing host tests, kept
    // independent because their fake is private and old fixtures must not change.
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var pending: CheckedContinuation<Void, Never>?
        var delayNext = true
        var active = 0, maxActive = 0
        var paths: [String] { requests.map { $0.url!.lastPathComponent } }
        var ids: [Int64] { requests.compactMap { request in
            guard request.url?.lastPathComponent == "detail", let body = request.httpBody,
                  let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
            return (object["id"] as? NSNumber)?.int64Value
        } }
        func waitForPending() async {
            for _ in 0..<500 { if pending != nil { return }; await Task.yield() }
            XCTFail("Synthetic read did not suspend")
        }
        func resume() { let waiter = pending; pending = nil; waiter?.resume() }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); active += 1; maxActive = max(maxActive, active)
            defer { active -= 1 }
            if delayNext { delayNext = false; await withCheckedContinuation { pending = $0 } }
            let data: Any
            if request.url?.lastPathComponent == "detail" {
                let object = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                let id = (object["id"] as! NSNumber).int64Value
                data = ["id": String(id), "applicationNo": "SYNTHETIC-\(id)", "status": "SUBMITTED",
                    "titleType": "PERSONAL", "titleName": "Synthetic title", "totalAmount": 1,
                    "orderCount": 1, "orders": [["orderId": "21", "amount": 1]]] as [String: Any]
            } else { data = [] as [Any] }
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": data]), 200)
        }
    }
}
